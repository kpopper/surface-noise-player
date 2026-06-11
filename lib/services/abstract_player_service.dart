import 'package:just_audio/just_audio.dart';
import '../models/release.dart';

abstract class AbstractPlayerService {
  Release? get currentRelease;
  Stream<SequenceState?> get sequenceStateStream;
  Stream<PlayerState> get playerStateStream;
  bool get hasPrevious;
  bool get hasNext;
  Future<void> seekToPrevious();
  Future<void> seekToNext();
  Future<void> play();
  Future<void> pause();
  Future<void> playRelease(Release release, {int trackIndex = 0});
  Future<void> playTrack(Release release, int trackIndex);
}
