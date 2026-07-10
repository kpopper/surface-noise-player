import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/abstract_player_service.dart';

class FakePlayerService implements AbstractPlayerService {
  final _sequenceStateController =
      StreamController<SequenceState?>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _errorMessageController = StreamController<String>.broadcast();

  @override
  Release? currentRelease;

  @override
  bool hasPrevious = false;

  @override
  bool hasNext = false;

  // Recorded calls
  bool playCalled = false;
  bool pauseCalled = false;
  Release? lastPlayedRelease;
  int? lastPlayedTrackIndex;
  Duration? seekedTo;

  @override
  Stream<SequenceState?> get sequenceStateStream =>
      _sequenceStateController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<String> get errorMessageStream => _errorMessageController.stream;

  @override
  Future<void> play() async => playCalled = true;

  @override
  Future<void> pause() async => pauseCalled = true;

  @override
  Future<void> seekToPrevious() async {}

  @override
  Future<void> seekToNext() async {}

  @override
  Future<void> seek(Duration position) async => seekedTo = position;

  @override
  Future<void> playRelease(Release release, {int trackIndex = 0}) async {
    currentRelease = release;
    lastPlayedRelease = release;
    lastPlayedTrackIndex = trackIndex;
  }

  @override
  Future<void> playTrack(Release release, int trackIndex) =>
      playRelease(release, trackIndex: trackIndex);

  void emitSequenceState(MediaItem tag) {
    final source = AudioSource.uri(Uri.file('/tmp/track.mp3'), tag: tag)
        as IndexedAudioSource;
    _sequenceStateController.add(SequenceState(
      sequence: [source],
      currentIndex: 0,
      shuffleIndices: const [0],
      shuffleModeEnabled: false,
      loopMode: LoopMode.off,
    ));
  }

  void clearSequenceState() {
    _sequenceStateController.add(null);
  }

  void emitPlayerState({
    required bool playing,
    ProcessingState processingState = ProcessingState.ready,
  }) {
    _playerStateController.add(PlayerState(playing, processingState));
  }

  void emitErrorMessage(String message) {
    _errorMessageController.add(message);
  }

  void dispose() {
    _sequenceStateController.close();
    _playerStateController.close();
    _positionController.close();
    _durationController.close();
    _errorMessageController.close();
  }
}
