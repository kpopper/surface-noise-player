import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/player_service.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_metadata_service.dart';

// just_audio talks to a real platform plugin by default, which isn't present
// under `flutter test`. Swapping in this trivial in-memory platform lets
// PlayerService's setAudioSource()/play() calls succeed without touching a
// real audio engine — these tests are about the download/timeout
// orchestration in PlayerService, not just_audio's own playback mechanics.
class _FakeJustAudioPlatform extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _FakeAudioPlayerPlatform(request.id);

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

class _FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  _FakeAudioPlayerPlatform(super.id);

  // just_audio's own _load() awaits the first non-"loading" processing
  // state derived from this stream before resolving — emit a "ready" event
  // once subscribed to (asynchronously, so the listener set up by
  // just_audio is already attached) or setAudioSource()/play() would hang
  // forever waiting for a transition that never comes.
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      Stream.fromFuture(Future(() => PlaybackEventMessage(
            processingState: ProcessingStateMessage.ready,
            updateTime: DateTime.now(),
            updatePosition: Duration.zero,
            bufferedPosition: Duration.zero,
            duration: null,
            icyMetadata: null,
            currentIndex: 0,
            androidAudioSessionId: null,
          ))).asBroadcastStream();

  @override
  Future<LoadResponse> load(LoadRequest request) async =>
      LoadResponse(duration: null);

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async =>
      DisposeResponse();

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
          ConcatenatingRemoveRangeRequest request) async =>
      ConcatenatingRemoveRangeResponse();

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
          ConcatenatingInsertAllRequest request) async =>
      ConcatenatingInsertAllResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  JustAudioPlatform.instance = _FakeJustAudioPlatform();

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
