import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/release.dart';
import 'abstract_player_service.dart';
import 'bookmark_service.dart';

class PlayerService implements AbstractPlayerService {
  static PlayerService? _instance;
  static PlayerService get instance => _instance ??= PlayerService._();

  // How often to re-check availability while waiting for a track to
  // download, and how long to wait before giving up and skipping it.
  static const _downloadPollInterval = Duration(seconds: 1);
  static const _downloadTimeout = Duration(minutes: 10);

  final AudioPlayer player = AudioPlayer();
  final BookmarkService _bookmarks;
  final _errorMessageController = StreamController<String>.broadcast();
  final _waitingController = StreamController<bool>.broadcast();
  StreamSubscription<PlayerException>? _errorStreamSub;
  StreamSubscription<ProcessingState>? _processingStateSub;

  // The release's full track list, in release order — the queue we step
  // through one track at a time. Unlike the old model, this is not filtered
  // down to only the tracks that were available when playback started.
  List<Track> _queue = [];
  int _currentIndex = -1;

  // Incremented on every call to _playAtIndex; lets an in-flight download
  // wait or load bail out cleanly if superseded by a newer one (skip tapped
  // mid-load, etc.) instead of acting on stale state.
  int _loadRequestId = 0;

  bool _waiting = false;

  // Set while _playAtIndex's own setAudioSource/play call is in flight, so
  // the errorStream/processingState listeners below don't also react to a
  // failure or completion this same call already handled.
  bool _manualLoadInProgress = false;
  DateTime? _lastErrorEmitAt;

  PlayerService._([BookmarkService? bookmarks])
      : _bookmarks = bookmarks ?? BookmarkService.instance {
    _errorStreamSub = player.errorStream.listen(_handleMidPlaybackError);
    _processingStateSub = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_manualLoadInProgress) {
        unawaited(_advanceOrStop(_currentIndex));
      }
    });
  }

  @override
  Release? currentRelease;

  @override
  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length) ? _queue[_currentIndex] : null;

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
  bool get isWaitingForDownload => _waiting;
  @override
  Stream<bool> get waitingForDownloadStream => _waitingController.stream;
  @override
  bool get hasPrevious => _currentIndex > 0;
  @override
  bool get hasNext => _currentIndex >= 0 && _currentIndex < _queue.length - 1;
  @override
  Future<void> seekToPrevious() => _playAtIndex(_currentIndex - 1);
  @override
  Future<void> seekToNext() => _playAtIndex(_currentIndex + 1);
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> playRelease(Release release, {int trackIndex = 0}) async {
    if (release.tracks.isEmpty) {
      _emitErrorMessage(null);
      await _stopPlayback();
      return;
    }
    currentRelease = release;
    _queue = release.tracks;
    await _playAtIndex(trackIndex.clamp(0, _queue.length - 1));
  }

  @override
  Future<void> playTrack(Release release, int trackIndex) =>
      playRelease(release, trackIndex: trackIndex);

  // Loads and plays a single track from the queue, requesting a download and
  // waiting (with a visible spinner) if it isn't locally available yet.
  // Every call gets a fresh requestId; a call whose id no longer matches
  // _loadRequestId by the time an await returns has been superseded by a
  // later call and abandons its work without touching shared state.
  Future<void> _playAtIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    final requestId = ++_loadRequestId;
    _setWaiting(false); // clear a stale spinner left by a superseded call
    final track = _queue[index];

    unawaited(_prefetchNext(index));

    if (!await _bookmarks.isFileAvailable(track.path)) {
      if (requestId != _loadRequestId) return;
      unawaited(_bookmarks.downloadFile(track.path));
      _setWaiting(true);
      final available = await _waitForAvailability(track.path, requestId);
      if (requestId != _loadRequestId) return;
      _setWaiting(false);
      if (!available) {
        _emitErrorMessage(track.title);
        await _advanceOrStop(index);
        return;
      }
    }

    if (requestId != _loadRequestId) return;
    _manualLoadInProgress = true;
    try {
      await player.setAudioSource(_buildSource(track));
      if (requestId != _loadRequestId) return;
      // player.play()'s Future only resolves when playback later
      // finishes/pauses/stops, not when it starts — must not be awaited
      // here, or _manualLoadInProgress would stay true (suppressing the
      // completed/error listeners below) for the whole song.
      unawaited(player.play());
    } on PlayerInterruptedException {
      // A newer _playAtIndex call superseded this one mid-load.
    } on PlayerException {
      if (requestId == _loadRequestId) {
        _emitErrorMessage(track.title);
        await _advanceOrStop(index);
      }
    } finally {
      _manualLoadInProgress = false;
    }
  }

  Future<void> _advanceOrStop(int fromIndex) async {
    final next = fromIndex + 1;
    if (next >= _queue.length) {
      await _stopPlayback();
    } else {
      await _playAtIndex(next);
    }
  }

  // Fire-and-forget: request the next track's download while the current
  // one plays, so it's more likely to already be available when needed.
  Future<void> _prefetchNext(int index) async {
    final next = index + 1;
    if (next >= _queue.length) return;
    final track = _queue[next];
    if (await _bookmarks.isFileAvailable(track.path)) return;
    await _bookmarks.downloadFile(track.path);
  }

  Future<bool> _waitForAvailability(String path, int requestId) async {
    final deadline = DateTime.now().add(_downloadTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (requestId != _loadRequestId) return false;
      if (await _bookmarks.isFileAvailable(path)) return true;
      await Future.delayed(_downloadPollInterval);
    }
    return false;
  }

  void _setWaiting(bool value) {
    if (_waiting == value) return;
    _waiting = value;
    _waitingController.add(value);
  }

  AudioSource _buildSource(Track track) => AudioSource.uri(
        Uri.file(track.path),
        tag: MediaItem(
          id: track.path,
          title: track.title,
          artist: track.artist ?? currentRelease?.albumArtist,
          album: currentRelease?.albumTitle ?? currentRelease?.name,
          artUri: currentRelease?.artPath != null
              ? Uri.file(currentRelease!.artPath!)
              : null,
        ),
      );

  void _handleMidPlaybackError(PlayerException error) {
    if (_manualLoadInProgress) return;
    final now = DateTime.now();
    if (_lastErrorEmitAt != null &&
        now.difference(_lastErrorEmitAt!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastErrorEmitAt = now;
    final title = (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _queue[_currentIndex].title
        : null;
    _errorMessageController.add(_friendlyMessage(title));
    unawaited(_advanceOrStop(_currentIndex));
  }

  void _emitErrorMessage(String? title) {
    _lastErrorEmitAt = DateTime.now();
    _errorMessageController.add(_friendlyMessage(title));
  }

  Future<void> _stopPlayback() async {
    currentRelease = null;
    _queue = [];
    _currentIndex = -1;
    ++_loadRequestId;
    _setWaiting(false);
    await player.pause();
    await player.clearAudioSources();
  }

  String _friendlyMessage(String? title) => title == null
      ? "Couldn't play track — check it's downloaded from iCloud."
      : "Couldn't play '$title' — check it's downloaded from iCloud.";

  void dispose() {
    _errorStreamSub?.cancel();
    _processingStateSub?.cancel();
    _errorMessageController.close();
    _waitingController.close();
    player.dispose();
  }
}
