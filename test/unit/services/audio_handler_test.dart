import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/audio_handler.dart';
import 'package:surface_noise_player/services/player_service.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_just_audio_platform.dart';
import '../../helpers/fake_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fakePlatform = FakeJustAudioPlatform();
  JustAudioPlatform.instance = fakePlatform;

  late FakeBookmarkService fakeBookmarks;
  late FakeMetadataService fakeMetadata;
  late PlayerService service;
  late SurfaceNoiseAudioHandler handler;

  Release releaseOf(String folderPath, String name, List<Track> tracks,
          {String? albumTitle, String? albumArtist, String? artPath}) =>
      Release(
        folderPath: folderPath,
        name: name,
        tracks: tracks,
        tags: const [],
        albumTitle: albumTitle,
        albumArtist: albumArtist,
        artPath: artPath,
      );

  // Positions keep advancing while the fake player is "playing", so compare
  // to within a second rather than exactly.
  Matcher closeToPosition(Duration expected) => isA<Duration>().having(
      (d) => (d - expected).inMilliseconds.abs(),
      'distance (ms)',
      lessThan(1000));

  setUp(() {
    fakeBookmarks = FakeBookmarkService();
    fakeMetadata = FakeMetadataService();
    service = PlayerService.forTest(
      bookmarks: fakeBookmarks,
      metadata: fakeMetadata,
      downloadPollInterval: const Duration(milliseconds: 5),
      downloadTimeout: const Duration(milliseconds: 200),
    );
    handler = SurfaceNoiseAudioHandler(service);
  });

  tearDown(() async {
    fakePlatform.loadDuration = null;
    await handler.dispose();
    service.dispose();
  });

  test(
      'updates the lock screen media item to the newly selected track before it finishes downloading',
      () async {
    final releaseOne = releaseOf(
      '/music/One',
      'Release One',
      [
        const Track(
            path: '/music/One/01.mp3', title: 'Old Track', trackNumber: 1)
      ],
      albumArtist: 'Old Artist',
    );
    final releaseTwo = releaseOf(
      '/music/Two',
      'Release Two',
      [
        const Track(
            path: '/music/Two/01.mp3', title: 'New Track', trackNumber: 1)
      ],
      albumTitle: 'Album Two',
      albumArtist: 'New Artist',
      artPath: '/music/Two/art.jpg',
    );

    await service.playRelease(releaseOne);
    expect(handler.mediaItem.valueOrNull?.title, 'Old Track');

    // Track 2 is never granted availability — it stays "downloading" for
    // the whole timeout, mirroring an offline/undownloaded track. Don't
    // await this: we want to observe state while the wait is in progress.
    fakeBookmarks.unavailablePaths = {'/music/Two/01.mp3'};
    final playFuture = service.playRelease(releaseTwo);

    // Let the synchronous currentTrack/currentRelease update and the
    // resulting waitingForDownloadStream event reach the handler, well
    // before the 200ms download timeout elapses.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final item = handler.mediaItem.valueOrNull;
    expect(item?.title, 'New Track');
    expect(item?.artist, 'New Artist');
    expect(item?.album, 'Album Two');
    expect(item?.artUri, Uri.file('/music/Two/art.jpg'));

    await playFuture; // let the timeout resolve cleanly before tearDown
  });

  test(
      'clears the native now-playing display once PlayerService stops itself after a failed download',
      () async {
    final releaseOne = releaseOf(
      '/music/One',
      'Release One',
      [
        const Track(
            path: '/music/One/01.mp3', title: 'Old Track', trackNumber: 1)
      ],
    );
    final releaseTwo = releaseOf(
      '/music/Two',
      'Release Two',
      [
        const Track(
            path: '/music/Two/01.mp3', title: 'New Track', trackNumber: 1)
      ],
    );

    await service.playRelease(releaseOne);
    expect(handler.playbackState.valueOrNull?.processingState,
        isNot(AudioProcessingState.idle));

    fakeBookmarks.unavailablePaths = {'/music/Two/01.mp3'};
    await service.playRelease(releaseTwo); // times out and stops itself

    expect(service.currentRelease, isNull);
    expect(handler.playbackState.valueOrNull?.processingState,
        AudioProcessingState.idle);
  });

  test('includes the loaded track\'s duration in the lock screen media item',
      () async {
    fakePlatform.loadDuration = const Duration(minutes: 3, seconds: 42);
    final release = releaseOf(
      '/music/One',
      'Release One',
      [const Track(path: '/music/One/01.mp3', title: 'Track', trackNumber: 1)],
    );

    await service.playRelease(release);
    await Future<void>.delayed(Duration.zero);

    final item = handler.mediaItem.valueOrNull;
    expect(item?.title, 'Track');
    expect(item?.duration, const Duration(minutes: 3, seconds: 42));
  });

  test(
      'shows no duration while the newly selected track is still downloading, rather than the previous track\'s',
      () async {
    fakePlatform.loadDuration = const Duration(minutes: 3);
    final releaseOne = releaseOf(
      '/music/One',
      'Release One',
      [
        const Track(
            path: '/music/One/01.mp3', title: 'Old Track', trackNumber: 1)
      ],
    );
    final releaseTwo = releaseOf(
      '/music/Two',
      'Release Two',
      [
        const Track(
            path: '/music/Two/01.mp3', title: 'New Track', trackNumber: 1)
      ],
    );

    await service.playRelease(releaseOne);
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.valueOrNull?.duration, const Duration(minutes: 3));

    fakeBookmarks.unavailablePaths = {'/music/Two/01.mp3'};
    final playFuture = service.playRelease(releaseTwo);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final item = handler.mediaItem.valueOrNull;
    expect(item?.title, 'New Track');
    expect(item?.duration, isNull);

    await playFuture;
  });

  test(
      'offers skip previous on the first track, restarting it rather than doing nothing',
      () async {
    final release = releaseOf(
      '/music/One',
      'Release One',
      [
        const Track(path: '/music/One/01.mp3', title: 'First', trackNumber: 1),
        const Track(path: '/music/One/02.mp3', title: 'Second', trackNumber: 2),
      ],
    );

    await service.playRelease(release);
    await service.seek(const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);

    final controls = handler.playbackState.valueOrNull?.controls ?? [];
    expect(controls, contains(MediaControl.skipToPrevious));

    await handler.skipToPrevious();
    await Future<void>.delayed(Duration.zero);

    expect(service.currentTrack?.title, 'First');
    expect(service.player.position, closeToPosition(Duration.zero));
  });

  test(
      'broadcasts the new elapsed position when a seek arrives from the native controls',
      () async {
    fakePlatform.loadDuration = const Duration(minutes: 3);
    final release = releaseOf(
      '/music/One',
      'Release One',
      [const Track(path: '/music/One/01.mp3', title: 'Track', trackNumber: 1)],
    );

    await service.playRelease(release);
    await handler.seek(const Duration(seconds: 90));
    await Future<void>.delayed(Duration.zero);

    expect(
        service.player.position, closeToPosition(const Duration(seconds: 90)));
    expect(handler.playbackState.valueOrNull?.updatePosition,
        closeToPosition(const Duration(seconds: 90)));
  });

  test('offers skip next on the last track, skipping to the end of the release',
      () async {
    final release = releaseOf(
      '/music/One',
      'Release One',
      [
        const Track(path: '/music/One/01.mp3', title: 'First', trackNumber: 1),
        const Track(path: '/music/One/02.mp3', title: 'Last', trackNumber: 2),
      ],
    );

    await service.playRelease(release, trackIndex: 1);
    await Future<void>.delayed(Duration.zero);

    final controls = handler.playbackState.valueOrNull?.controls ?? [];
    expect(controls, contains(MediaControl.skipToNext));

    await handler.skipToNext();
    await Future<void>.delayed(Duration.zero);

    expect(service.currentRelease, isNull);
    expect(service.currentTrack, isNull);
    expect(handler.playbackState.valueOrNull?.processingState,
        AudioProcessingState.idle);
  });
}
