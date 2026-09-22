import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

// just_audio talks to a real platform plugin by default, which isn't present
// under `flutter test`. Swapping in this trivial in-memory platform (via
// `JustAudioPlatform.instance = FakeJustAudioPlatform()`) lets an AudioPlayer's
// setAudioSource()/play() calls succeed without touching a real audio engine
// — for tests that are about orchestration logic built on top of just_audio,
// not just_audio's own playback mechanics.
class FakeJustAudioPlatform extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      FakeAudioPlayerPlatform(request.id);

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  FakeAudioPlayerPlatform(super.id);

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
