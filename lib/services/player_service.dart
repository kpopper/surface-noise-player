import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/release.dart';
import 'abstract_player_service.dart';

class PlayerService implements AbstractPlayerService {
  static PlayerService? _instance;
  static PlayerService get instance => _instance ??= PlayerService._();

  // Bounds how many consecutive mid-playback failures just_audio will
  // auto-skip past (e.g. a whole side of an offline album) before giving up
  // and pausing, so a systemic iCloud outage can't trigger an unbroken skip
  // storm.
  static const int _maxConsecutiveSkips = 10;

  final AudioPlayer player = AudioPlayer(maxSkipsOnError: _maxConsecutiveSkips);
  final _errorMessageController = StreamController<String>.broadcast();
  StreamSubscription<PlayerException>? _errorStreamSub;
  StreamSubscription<ProcessingState>? _processingStateSub;

  // Set while playRelease's own retry loop is reporting failures, so the
  // errorStream listener below doesn't also report the same initial-track
  // failure a second time.
  bool _manualLoadInProgress = false;
  DateTime? _lastErrorEmitAt;

  PlayerService._() {
    _errorStreamSub = player.errorStream.listen(_handleMidPlaybackError);
    // ProcessingState.completed only fires once the whole queue has finished
    // (not between auto-advancing tracks), so this is the signal for
    // reaching the end of a release with everything having played fine.
    _processingStateSub = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _stopPlayback();
    });
  }

  @override
  Release? currentRelease;

  @override
  Stream<SequenceState?> get sequenceStateStream => player.sequenceStateStream;
  @override
  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  @override
  Stream<Duration> get positionStream => player.positionStream;
  @override
  Stream<Duration?> get durationStream => player.durationStream;
  @override
  Stream<String> get errorMessageStream => _errorMessageController.stream;
  @override
  bool get hasPrevious => player.hasPrevious;
  @override
  bool get hasNext => player.hasNext;
  @override
  Future<void> seekToPrevious() => _seekWithFallback(-1);
  @override
  Future<void> seekToNext() => _seekWithFallback(1);
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> playRelease(Release release, {int trackIndex = 0}) async {
    currentRelease = release;
    final sources = _buildSources(release);
    _manualLoadInProgress = true;
    try {
      for (var index = trackIndex; index < sources.length; index++) {
        try {
          await player.setAudioSources(sources, initialIndex: index);
          await player.play();
          return;
        } on PlayerInterruptedException {
          // A newer playRelease/playTrack call superseded this one mid-load.
          return;
        } on PlayerException {
          _emitErrorMessage(release.tracks[index].title);
        }
      }
      // Every candidate track from trackIndex onward failed to load; nothing
      // to play, so stop and clear rather than leaving a stale unplayable
      // track showing in the mini player.
      await _stopPlayback();
    } finally {
      _manualLoadInProgress = false;
    }
  }

  @override
  Future<void> playTrack(Release release, int trackIndex) =>
      playRelease(release, trackIndex: trackIndex);

  // Manual seek to a specific step direction, cascading forward/backward
  // through the tracklist on failure. Needed because a direct
  // player.seekToNext()/seekToPrevious() call can throw synchronously for an
  // unplayable target (unlike the "spontaneous" mid-sequence failures that
  // surface via player.errorStream and are handled by _handleMidPlaybackError).
  Future<void> _seekWithFallback(int step) async {
    final release = currentRelease;
    final total = release?.tracks.length ?? 0;
    var index = (player.currentIndex ?? 0) + step;
    if (total == 0 || index < 0 || index >= total) return;
    _manualLoadInProgress = true;
    try {
      while (index >= 0 && index < total) {
        try {
          await player.seek(Duration.zero, index: index);
          await player.play();
          return;
        } on PlayerInterruptedException {
          return;
        } on Exception {
          _emitErrorMessage(release!.tracks[index].title);
          index += step;
        }
      }
      await _stopPlayback();
    } finally {
      _manualLoadInProgress = false;
    }
  }

  List<AudioSource> _buildSources(Release release) => release.tracks
      .map((t) => AudioSource.uri(
            Uri.file(t.path),
            tag: MediaItem(
              id: t.path,
              title: t.title,
              artist: t.artist ?? release.albumArtist,
              album: release.albumTitle ?? release.name,
              artUri:
                  release.artPath != null ? Uri.file(release.artPath!) : null,
            ),
          ))
      .toList();

  void _handleMidPlaybackError(PlayerException error) {
    if (_manualLoadInProgress) return;
    final now = DateTime.now();
    if (_lastErrorEmitAt != null &&
        now.difference(_lastErrorEmitAt!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastErrorEmitAt = now;
    _errorMessageController.add(_friendlyMessage(_trackTitleForIndex(error.index)));
    // just_audio's own maxSkipsOnError machinery already pauses when there's
    // no next track, but stop and clear here too so the mini player closes
    // rather than continuing to show the last (unplayable) track.
    if (!player.hasNext) {
      _stopPlayback();
    }
  }

  void _emitErrorMessage(String? title) {
    _lastErrorEmitAt = DateTime.now();
    _errorMessageController.add(_friendlyMessage(title));
  }

  Future<void> _stopPlayback() async {
    currentRelease = null;
    await player.pause();
    await player.clearAudioSources();
  }

  String _friendlyMessage(String? title) => title == null
      ? "Couldn't play track — check it's downloaded from iCloud."
      : "Couldn't play '$title' — check it's downloaded from iCloud.";

  String? _trackTitleForIndex(int? index) {
    final release = currentRelease;
    if (release == null || index == null || index < 0 || index >= release.tracks.length) {
      return null;
    }
    return release.tracks[index].title;
  }

  void dispose() {
    _errorStreamSub?.cancel();
    _processingStateSub?.cancel();
    _errorMessageController.close();
    player.dispose();
  }
}
