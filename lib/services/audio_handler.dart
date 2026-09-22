import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'player_service.dart';

// Bridges native media controls (lock screen, Control Center, headset
// buttons) to PlayerService's own queue navigation, rather than relying on
// audio_service/just_audio_background's built-in queue handling.
//
// PlayerService loads one track at a time via player.setAudioSource() —
// required by the download-on-request design, since the player can't be
// handed a source for a file that isn't downloaded yet. That means
// just_audio's own sequence is always a single item, so anything driven by
// the player's own hasNext/hasPrevious (as just_audio_background's bundled
// handler does) never sees a "next" or "previous" track to skip to, and
// native skip controls are never enabled. Driving skipToNext/skipToPrevious
// through PlayerService's own hasNext/hasPrevious/seekToNext/seekToPrevious
// instead — the same queue-navigation PlayerService already exposes to the
// on-screen skip buttons — fixes that without changing how tracks are
// loaded.
class SurfaceNoiseAudioHandler extends BaseAudioHandler {
  final PlayerService _player;
  late final StreamSubscription _sequenceStateSub;
  late final StreamSubscription _playerStateSub;
  late final StreamSubscription _waitingSub;
  late final StreamSubscription _positionSub;

  SurfaceNoiseAudioHandler([PlayerService? player])
      : _player = player ?? PlayerService.instance {
    _sequenceStateSub =
        _player.sequenceStateStream.listen((_) => _broadcastMediaItem());
    _playerStateSub = _player.playerStateStream.listen((_) => _broadcastState());
    _waitingSub = _player.waitingForDownloadStream.listen((_) {
      // A newly requested track updates PlayerService.currentTrack /
      // currentRelease synchronously, well before just_audio has a loaded
      // source for it (or may never, if the download times out) — refresh
      // the lock screen/Control Center info from those immediately rather
      // than leaving the previous track's details showing for the whole
      // download wait.
      _broadcastMediaItem();
      _broadcastState();
    });
    _positionSub = _player.positionStream.listen((_) => _broadcastState());
    _broadcastMediaItem();
    _broadcastState();
  }

  // Prefers the just_audio-loaded tag, but only once it actually matches
  // the currently requested track — otherwise it's still the previous
  // track's tag, left over until the new one finishes downloading and
  // loading. Falls back to a MediaItem built from PlayerService's own
  // currentTrack/currentRelease, mirroring _buildSource in player_service.
  void _broadcastMediaItem() {
    final loadedTag = _player.player.sequenceState.currentSource?.tag;
    final tag = loadedTag is MediaItem ? loadedTag : null;
    final pendingTrack = _player.currentTrack;
    if (tag == null && pendingTrack == null) {
      // Nothing is playing or about to play (PlayerService has stopped
      // itself entirely, e.g. a download that never completed) — clear the
      // native now-playing display instead of leaving the previous track's
      // info showing, paused, with nothing driving it further.
      unawaited(super.stop());
      return;
    }
    final tagIsCurrent =
        tag != null && (pendingTrack == null || tag.id == pendingTrack.path);
    if (tagIsCurrent) {
      mediaItem.add(tag);
      return;
    }
    final release = _player.currentRelease;
    mediaItem.add(MediaItem(
      id: pendingTrack!.path,
      title: pendingTrack.title,
      artist: pendingTrack.artist ?? release?.albumArtist,
      album: release?.albumTitle ?? release?.name,
      artUri:
          release?.artPath != null ? Uri.file(release!.artPath!) : null,
    ));
  }

  void _broadcastState() {
    final playing = _player.player.playing;
    final controls = [
      if (_player.hasPrevious) MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      if (_player.hasNext) MediaControl.skipToNext,
    ];
    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: List.generate(controls.length, (i) => i)
          .where((i) => controls[i].action != MediaAction.stop)
          .toList(),
      processingState: _player.isWaitingForDownload
          ? AudioProcessingState.buffering
          : _processingStateFrom(_player.player.processingState),
      playing: playing,
      updatePosition: _player.player.position,
      bufferedPosition: _player.player.bufferedPosition,
      speed: _player.player.speed,
    ));
  }

  AudioProcessingState _processingStateFrom(ProcessingState state) =>
      switch (state) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> stop() async {
    await _player.pause();
    await super.stop();
  }

  Future<void> dispose() async {
    await _sequenceStateSub.cancel();
    await _playerStateSub.cancel();
    await _waitingSub.cancel();
    await _positionSub.cancel();
  }
}
