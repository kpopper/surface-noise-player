import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/abstract_player_service.dart';
import '../services/player_service.dart';
import '../widgets/art_thumbnail.dart';

class NowPlayingScreen extends StatefulWidget {
  final AbstractPlayerService? playerService;
  const NowPlayingScreen({super.key, this.playerService});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  late AbstractPlayerService _svc;
  double? _dragValue;
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

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
      body: StreamBuilder<SequenceState?>(
        stream: _svc.sequenceStateStream,
        builder: (context, seqSnap) {
          return StreamBuilder<bool>(
            stream: _svc.waitingForDownloadStream,
            initialData: _svc.isWaitingForDownload,
            builder: (context, waitingSnap) {
              // The loaded MediaItem tag reflects what just_audio actually
              // has queued; _svc.currentTrack is set as soon as playback is
              // requested, even before a download-wait completes and a
              // source is loaded — fall back to it so this screen shows
              // something immediately when opened during a download wait,
              // rather than staying blank until just_audio has a source.
              final tag = seqSnap.data?.currentSource?.tag as MediaItem?;
              final pendingTrack = _svc.currentTrack;
              if (tag == null && pendingTrack == null) {
                return const SizedBox.shrink();
              }
              final title = tag?.title ?? pendingTrack!.title;
              final artist = tag?.artist ??
                  pendingTrack?.artist ??
                  _svc.currentRelease?.albumArtist;
              final album = tag?.album ??
                  _svc.currentRelease?.albumTitle ??
                  _svc.currentRelease?.name;
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
                        style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (album != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        album,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 24),
                    StreamBuilder<Duration?>(
                      stream: _svc.durationStream,
                      builder: (context, durSnap) {
                        final duration = durSnap.data ?? Duration.zero;
                        return StreamBuilder<Duration>(
                          stream: _svc.positionStream,
                          builder: (context, posSnap) {
                            final position = posSnap.data ?? Duration.zero;
                            final maxMs = duration.inMilliseconds.toDouble();
                            final value = (_dragValue ??
                                    position.inMilliseconds
                                        .clamp(0, duration.inMilliseconds)
                                        .toDouble())
                                .clamp(0, maxMs > 0 ? maxMs : 1)
                                .toDouble();

                            return Column(
                              children: [
                                Slider(
                                  value: value,
                                  max: maxMs > 0 ? maxMs : 1,
                                  onChanged: (v) =>
                                      setState(() => _dragValue = v),
                                  onChangeEnd: (v) {
                                    setState(() => _dragValue = null);
                                    _svc.seek(
                                        Duration(milliseconds: v.toInt()));
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_format(position),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey)),
                                      Text(_format(duration),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<PlayerState>(
                      stream: _svc.playerStateStream,
                      builder: (context, stateSnap) {
                        final state = stateSnap.data;
                        final playing = (state?.playing ?? false) &&
                            state?.processingState != ProcessingState.completed;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 40,
                              icon: const Icon(Icons.skip_previous),
                              onPressed:
                                  _svc.hasPrevious ? _svc.seekToPrevious : null,
                            ),
                            const SizedBox(width: 16),
                            if (isWaiting)
                              const SizedBox(
                                width: 64,
                                height: 64,
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child:
                                      CircularProgressIndicator(strokeWidth: 3),
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
                              onPressed: _svc.hasNext ? _svc.seekToNext : null,
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
    );
  }
}
