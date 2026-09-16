import 'package:just_audio/just_audio.dart';
import '../models/release.dart';

abstract class AbstractPlayerService {
  Release? get currentRelease;
  // The track playback is currently on, set as soon as it's requested —
  // before it has necessarily finished downloading or been handed to the
  // underlying player. Use this (rather than sequenceStateStream) to show
  // "what's being played" immediately, including during the download wait.
  Track? get currentTrack;
  Stream<SequenceState?> get sequenceStateStream;
  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<String> get errorMessageStream;
  bool get hasPrevious;
  bool get hasNext;
  // True while playback is paused waiting for the current track to finish
  // downloading from iCloud.
  bool get isWaitingForDownload;
  Stream<bool> get waitingForDownloadStream;
  Future<void> seekToPrevious();
  Future<void> seekToNext();
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> playRelease(Release release, {int trackIndex = 0});
  Future<void> playTrack(Release release, int trackIndex);
}
