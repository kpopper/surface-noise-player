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

  @override
  void initState() {
    super.initState();
    _svc = widget.playerService ?? PlayerService.instance;
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
      body: StreamBuilder<SequenceState?>(
        stream: _svc.sequenceStateStream,
        builder: (context, seqSnap) {
          final tag = seqSnap.data?.currentSource?.tag;
          if (tag == null) return const SizedBox.shrink();
          final item = tag as MediaItem;

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
                  item.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (item.artist != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.artist!,
                    style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (item.album != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.album!,
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
                              onChanged: (v) => setState(() => _dragValue = v),
                              onChangeEnd: (v) {
                                setState(() => _dragValue = null);
                                _svc.seek(Duration(milliseconds: v.toInt()));
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_format(position),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(_format(duration),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                    final playing = stateSnap.data?.playing ?? false;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: _svc.hasPrevious ? _svc.seekToPrevious : null,
                        ),
                        const SizedBox(width: 16),
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
      ),
    );
  }
}
