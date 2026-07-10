import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/abstract_player_service.dart';
import '../services/player_service.dart';
import 'art_thumbnail.dart';

class MiniPlayer extends StatelessWidget {
  final AbstractPlayerService? playerService;
  final VoidCallback? onTap;

  const MiniPlayer({super.key, this.playerService, this.onTap});

  @override
  Widget build(BuildContext context) {
    final svc = playerService ?? PlayerService.instance;

    return StreamBuilder<SequenceState?>(
      stream: svc.sequenceStateStream,
      builder: (context, seqSnap) {
        final tag = seqSnap.data?.currentSource?.tag;
        if (tag == null) return const SizedBox.shrink();
        final item = tag as MediaItem;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Row(
            children: [
              ArtThumbnail(artPath: svc.currentRelease?.artPath, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (item.album != null)
                        Text(item.album!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: svc.playerStateStream,
                builder: (context, stateSnap) {
                  final state = stateSnap.data;
                  final playing = (state?.playing ?? false) &&
                      state?.processingState != ProcessingState.completed;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: svc.hasPrevious ? svc.seekToPrevious : null,
                      ),
                      IconButton(
                        iconSize: 34,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: playing ? svc.pause : svc.play,
                      ),
                      IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.skip_next),
                        onPressed: svc.hasNext ? svc.seekToNext : null,
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
  }
}
