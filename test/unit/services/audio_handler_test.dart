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
  JustAudioPlatform.instance = FakeJustAudioPlatform();

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
    await handler.dispose();
    service.dispose();
  });

  test(
      'updates the lock screen media item to the newly selected track before it finishes downloading',
      () async {
    final releaseOne = releaseOf(
      '/music/One',
      'Release One',
      [const Track(path: '/music/One/01.mp3', title: 'Old Track', trackNumber: 1)],
      albumArtist: 'Old Artist',
    );
    final releaseTwo = releaseOf(
      '/music/Two',
      'Release Two',
      [const Track(path: '/music/Two/01.mp3', title: 'New Track', trackNumber: 1)],
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
      [const Track(path: '/music/One/01.mp3', title: 'Old Track', trackNumber: 1)],
    );
    final releaseTwo = releaseOf(
      '/music/Two',
      'Release Two',
      [const Track(path: '/music/Two/01.mp3', title: 'New Track', trackNumber: 1)],
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
}
