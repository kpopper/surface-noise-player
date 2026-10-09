import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../services/abstract_player_service.dart';
import '../services/player_service.dart';
import '../widgets/art_thumbnail.dart';
import '../widgets/now_playing_details.dart';
import '../widgets/playback_progress.dart';

class NowPlayingScreen extends StatefulWidget {
  final AbstractPlayerService? playerService;
  const NowPlayingScreen({super.key, this.playerService});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  late AbstractPlayerService _svc;
  double _dismissDragExtent = 0;
  StreamSubscription<SequenceState?>? _sequenceSub;

  @override
  void initState() {
    super.initState();
    _svc = widget.playerService ?? PlayerService.instance;
    // Playback stopping (queue finished/exhausted) clears the current
    // source; if this screen is still open and on top, close it rather than
    // leaving a blank now-playing view behind.
    _sequenceSub = _svc.sequenceStateStream.listen((state) {
      if (state?.currentSource?.tag != null) return;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _sequenceSub?.cancel();
    super.dispose();
  }

  void _onDismissDragUpdate(DragUpdateDetails details) {
    _dismissDragExtent += details.delta.dy;
  }

  void _onDismissDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final shouldDismiss = _dismissDragExtent > 100 || velocity > 700;
    _dismissDragExtent = 0;
    if (shouldDismiss) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      // Both stream builders are kept unconditionally in the tree (neither
      // short-circuits to a hidden widget on its own) so each stays mounted
      // and subscribed regardless of which stream fires first — otherwise an
      // early "nothing to show" return from the outer builder would prevent
      // the inner one from ever mounting to catch a later event, and this
      // screen would stay blank when opened during a download wait.
      body: GestureDetector(
        key: const Key('now-playing-dismiss-area'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onDismissDragUpdate,
        onVerticalDragEnd: _onDismissDragEnd,
        child: StreamBuilder<SequenceState?>(
          stream: _svc.sequenceStateStream,
          builder: (context, seqSnap) {
            return StreamBuilder<bool>(
              stream: _svc.waitingForDownloadStream,
              initialData: _svc.isWaitingForDownload,
              builder: (context, waitingSnap) {
                final details = resolveNowPlayingDetails(
                    _svc, seqSnap.data?.currentSource?.tag as MediaItem?);
                if (details == null) return const SizedBox.shrink();
                final (:title, :artist, :album) = details;
                final isWaiting = waitingSnap.data ?? false;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      ArtThumbnail(
                        artPath: _svc.currentRelease?.artPath,
                        size: MediaQuery.of(context).size.width - 48,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      if (artist != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          artist,
                          style:
                              TextStyle(fontSize: 16, color: Colors.grey[400]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (album != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          album,
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 24),
                      PlaybackProgress(svc: _svc),
                      const SizedBox(height: 8),
                      StreamBuilder<PlayerState>(
                        stream: _svc.playerStateStream,
                        builder: (context, stateSnap) {
                          final state = stateSnap.data;
                          final playing = (state?.playing ?? false) &&
                              state?.processingState !=
                                  ProcessingState.completed;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 40,
                                icon: const Icon(Icons.skip_previous),
                                onPressed: _svc.hasPrevious
                                    ? _svc.seekToPrevious
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              if (isWaiting)
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: const CircleBorder(),
                                    padding: const EdgeInsets.all(20),
                                  ),
                                  onPressed: _svc.cancelDownloadWait,
                                  child: const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  ),
                                )
                              else
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: const CircleBorder(),
                                    padding: const EdgeInsets.all(16),
                                  ),
                                  onPressed: playing ? _svc.pause : _svc.play,
                                  child: Icon(
                                    playing ? Icons.pause : Icons.play_arrow,
                                    size: 36,
                                  ),
                                ),
                              const SizedBox(width: 16),
                              IconButton(
                                iconSize: 40,
                                icon: const Icon(Icons.skip_next),
                                onPressed:
                                    _svc.hasNext ? _svc.seekToNext : null,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
