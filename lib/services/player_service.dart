import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/release.dart';
import 'abstract_player_service.dart';
import 'bookmark_service.dart';

class PlayerService implements AbstractPlayerService {
  static PlayerService? _instance;
  static PlayerService get instance => _instance ??= PlayerService._();

  // Bounds how many consecutive mid-playback failures just_audio will
  // auto-skip past before giving up and pausing, so a systemic failure can't
  // trigger an unbroken skip storm. Kept as a fallback for tracks that pass
  // the availability check but still fail to decode; unavailable tracks are
  // now filtered out before ever being queued (see playRelease), since a
  // failed auto-advance into an evicted iCloud placeholder isn't reliably
  // reported back to Flutter.
  static const int _maxConsecutiveSkips = 10;

  final AudioPlayer player = AudioPlayer(maxSkipsOnError: _maxConsecutiveSkips);
  final BookmarkService _bookmarks;
  final _errorMessageController = StreamController<String>.broadcast();
  StreamSubscription<PlayerException>? _errorStreamSub;
  StreamSubscription<ProcessingState>? _processingStateSub;

  // The tracks actually handed to just_audio for the current queue, in
  // sequence order — a subset of currentRelease.tracks with unavailable
  // files filtered out, so sequence indices line up with this list, not with
  // currentRelease.tracks.
  List<Track> _loadedTracks = [];

  // Set while playRelease's/_seekWithFallback's own loop is reporting
  // failures, so the errorStream/processingState listeners below don't also
  // report or act on the same failure a second time.
  bool _manualLoadInProgress = false;
  DateTime? _lastErrorEmitAt;

  PlayerService._([BookmarkService? bookmarks])
      : _bookmarks = bookmarks ?? BookmarkService.instance {
    _errorStreamSub = player.errorStream.listen(_handleMidPlaybackError);
    _processingStateSub = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_manualLoadInProgress) {
        _stopPlayback();
      }
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
    final playable = <Track>[];
    for (var i = trackIndex; i < release.tracks.length; i++) {
      final track = release.tracks[i];
      if (await _bookmarks.isFileAvailable(track.path)) {
        playable.add(track);
      } else {
        _emitErrorMessage(track.title);
      }
    }
    if (playable.isEmpty) {
      await _stopPlayback();
      return;
    }
    _loadedTracks = playable;
    final sources = _buildSources(release, playable);
    _manualLoadInProgress = true;
    try {
      for (var index = 0; index < playable.length; index++) {
        try {
          await player.setAudioSources(sources, initialIndex: index);
          await player.play();
          return;
        } on PlayerInterruptedException {
          // A newer playRelease/playTrack call superseded this one mid-load.
          return;
        } on PlayerException {
          _emitErrorMessage(playable[index].title);
        }
      }
      // Every candidate track failed to load despite existing on disk (e.g.
      // corrupt file); nothing to play, so stop and clear.
      await _stopPlayback();
    } finally {
      _manualLoadInProgress = false;
    }
  }

  @override
  Future<void> playTrack(Release release, int trackIndex) =>
      playRelease(release, trackIndex: trackIndex);

  // Manual seek to a specific step direction, cascading forward/backward
  // through the loaded tracklist on failure. Needed because a direct
  // player.seekToNext()/seekToPrevious() call can throw synchronously for an
  // unplayable target (unlike the "spontaneous" mid-sequence failures that
  // surface via player.errorStream and are handled by _handleMidPlaybackError).
  Future<void> _seekWithFallback(int step) async {
    final tracks = _loadedTracks;
    final total = tracks.length;
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
          _emitErrorMessage(tracks[index].title);
          index += step;
        }
      }
      await _stopPlayback();
    } finally {
      _manualLoadInProgress = false;
    }
  }

  List<AudioSource> _buildSources(Release release, List<Track> tracks) =>
      tracks
          .map((t) => AudioSource.uri(
                Uri.file(t.path),
                tag: MediaItem(
                  id: t.path,
                  title: t.title,
                  artist: t.artist ?? release.albumArtist,
                  album: release.albumTitle ?? release.name,
                  artUri: release.artPath != null
                      ? Uri.file(release.artPath!)
                      : null,
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
    if (_isLastTrackIndex(error.index)) {
      _stopPlayback();
    }
  }

  bool _isLastTrackIndex(int? index) {
    if (_loadedTracks.isEmpty || index == null) return !player.hasNext;
    return index >= _loadedTracks.length - 1;
  }

  void _emitErrorMessage(String? title) {
    _lastErrorEmitAt = DateTime.now();
    _errorMessageController.add(_friendlyMessage(title));
  }

  Future<void> _stopPlayback() async {
    currentRelease = null;
    _loadedTracks = [];
    await player.pause();
    await player.clearAudioSources();
  }

  String _friendlyMessage(String? title) => title == null
      ? "Couldn't play track — check it's downloaded from iCloud."
      : "Couldn't play '$title' — check it's downloaded from iCloud.";

  String? _trackTitleForIndex(int? index) {
    if (index == null || index < 0 || index >= _loadedTracks.length) {
      return null;
    }
    return _loadedTracks[index].title;
  }

  void dispose() {
    _errorStreamSub?.cancel();
    _processingStateSub?.cancel();
    _errorMessageController.close();
    player.dispose();
  }
}
