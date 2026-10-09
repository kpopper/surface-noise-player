import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../services/abstract_player_service.dart';
import '../services/player_service.dart';
import 'art_thumbnail.dart';
import 'now_playing_details.dart';

class MiniPlayer extends StatelessWidget {
  final AbstractPlayerService? playerService;
  final VoidCallback? onTap;

  const MiniPlayer({super.key, this.playerService, this.onTap});

  @override
  Widget build(BuildContext context) {
    final svc = playerService ?? PlayerService.instance;

    // Both stream builders are kept unconditionally in the tree (neither
    // short-circuits to a hidden widget on its own) so each stays mounted
    // and subscribed regardless of which stream fires first — otherwise an
    // early "nothing to show" return from the outer builder would prevent
    // the inner one from ever mounting to catch a later event, and the
    // spinner would never appear (see the regression this guards against).
    return StreamBuilder<SequenceState?>(
      stream: svc.sequenceStateStream,
      builder: (context, seqSnap) {
        return StreamBuilder<bool>(
          stream: svc.waitingForDownloadStream,
          initialData: svc.isWaitingForDownload,
          builder: (context, waitingSnap) {
            final details = resolveNowPlayingDetails(
                svc, seqSnap.data?.currentSource?.tag as MediaItem?);
            if (details == null) return const SizedBox.shrink();
            final title = details.title;
            final album = details.album;
            final isWaiting = waitingSnap.data ?? false;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (details) {
                final velocity = details.velocity.pixelsPerSecond.dy;
                if (velocity < -250) onTap?.call();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Row(
                  children: [
                    ArtThumbnail(
                        artPath: svc.currentRelease?.artPath, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onTap,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            if (album != null)
                              Text(album,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.grey)),
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
                              onPressed:
                                  svc.hasPrevious ? svc.seekToPrevious : null,
                            ),
                            if (isWaiting)
                              IconButton(
                                iconSize: 34,
                                tooltip: 'Cancel',
                                icon: const SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5),
                                  ),
                                ),
                                onPressed: svc.cancelDownloadWait,
                              )
                            else
                              IconButton(
                                iconSize: 34,
                                icon: Icon(
                                    playing ? Icons.pause : Icons.play_arrow),
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
              ),
            );
          },
        );
      },
    );
  }
}
