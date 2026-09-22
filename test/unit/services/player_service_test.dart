import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:surface_noise_player/models/release.dart';
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

  Release releaseOf(List<Track> tracks) => Release(
        folderPath: '/release',
        name: 'Test Release',
        tracks: tracks,
        tags: const [],
      );

  setUp(() {
    fakeBookmarks = FakeBookmarkService();
    fakeMetadata = FakeMetadataService();
    service = PlayerService.forTest(
      bookmarks: fakeBookmarks,
      metadata: fakeMetadata,
      downloadPollInterval: Duration.zero,
      downloadTimeout: const Duration(milliseconds: 50),
    );
  });

  group('requesting the whole release', () {
    test(
        'is deferred until the requested track is confirmed available, then fires',
        () async {
      final release = releaseOf([
        const Track(path: '/release/01.mp3', title: 'One', trackNumber: 1),
        const Track(path: '/release/02.mp3', title: 'Two', trackNumber: 2),
      ]);
      fakeBookmarks.unavailablePaths = {'/release/01.mp3'};
      fakeBookmarks.downloadFileGrantsAvailability = true;

      await service.playRelease(release);

      expect(fakeBookmarks.downloadFileCalls, ['/release/01.mp3']);
      expect(fakeBookmarks.downloadReleaseCalls, ['/release']);
    });

    test('is never requested if the track times out without becoming available',
        () async {
      final release = releaseOf([
        const Track(path: '/release/01.mp3', title: 'One', trackNumber: 1),
        const Track(path: '/release/02.mp3', title: 'Two', trackNumber: 2),
      ]);
      fakeBookmarks.unavailablePaths = {'/release/01.mp3'};
      // downloadFileGrantsAvailability left false — the download request
      // never actually completes, simulating iCloud never delivering it.

      await service.playRelease(release);

      expect(fakeBookmarks.downloadReleaseCalls, isEmpty);
    });
  });

  group('selecting a new track', () {
    test(
        'stops any currently playing audio immediately, even if the new track is unavailable',
        () async {
      final release = releaseOf([
        const Track(path: '/release/01.mp3', title: 'One', trackNumber: 1),
        const Track(path: '/release/02.mp3', title: 'Two', trackNumber: 2),
      ]);

      await service.playRelease(release);
      expect(service.player.playing, isTrue);

      fakeBookmarks.unavailablePaths = {'/release/02.mp3'};
      final future = service.seekToNext();

      // The old track is paused synchronously, as soon as the new track is
      // selected — not only once its own download wait resolves (or times
      // out), by which point the mini player/lock screen already show the
      // newly selected track's details.
      expect(service.player.playing, isFalse);

      await future;
    });
  });

  group('a track that never becomes available', () {
    test('shows exactly one message and stops playback cleanly', () async {
      final release = releaseOf([
        const Track(path: '/release/01.mp3', title: 'One', trackNumber: 1),
      ]);
      fakeBookmarks.unavailablePaths = {'/release/01.mp3'};

      final messages = <String>[];
      final sub = service.errorMessageStream.listen(messages.add);

      await service.playRelease(release);
      // Let the broadcast stream event land.
      await Future<void>.delayed(Duration.zero);

      expect(messages, hasLength(1));
      expect(service.currentRelease, isNull);
      expect(service.isWaitingForDownload, isFalse);

      await sub.cancel();
    });

    test(
        'does not cascade into trying the next track in the release',
        () async {
      final release = releaseOf([
        const Track(path: '/release/01.mp3', title: 'One', trackNumber: 1),
        const Track(path: '/release/02.mp3', title: 'Two', trackNumber: 2),
      ]);
      fakeBookmarks.unavailablePaths = {'/release/01.mp3'};

      await service.playRelease(release);

      // Only the requested (first) track's download was ever attempted.
      expect(fakeBookmarks.downloadFileCalls, ['/release/01.mp3']);
    });

    test(
        'reached via advancing past the current track also stops rather than trying further tracks',
        () async {
      final release = releaseOf([
        const Track(path: '/release/01.mp3', title: 'One', trackNumber: 1),
        const Track(path: '/release/02.mp3', title: 'Two', trackNumber: 2),
        const Track(path: '/release/03.mp3', title: 'Three', trackNumber: 3),
      ]);
      // Track 1 is available and plays; skipping to track 2 (unavailable,
      // never downloads) should stop there rather than falling through to
      // track 3.
      fakeBookmarks.unavailablePaths = {'/release/02.mp3'};

      await service.playRelease(release);
      expect(service.currentRelease, isNotNull);

      final messages = <String>[];
      final sub = service.errorMessageStream.listen(messages.add);

      await service.seekToNext();
      await Future<void>.delayed(Duration.zero);

      expect(messages, hasLength(1));
      expect(service.currentRelease, isNull);
      expect(fakeBookmarks.downloadFileCalls, contains('/release/02.mp3'));
      expect(fakeBookmarks.downloadFileCalls, isNot(contains('/release/03.mp3')));

      await sub.cancel();
    });
  });
}
