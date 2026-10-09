import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/abstract_player_service.dart';
import '../services/player_service.dart';
import 'art_thumbnail.dart';
import 'now_playing_details.dart';
import 'playback_progress.dart';

const double kFloatingPlayerMaxWidth = 560;
// Gap between the floating player and the bottom of the window.
const double kFloatingPlayerMargin = 16;
// Empty space to leave at the end of scrolling content beneath the floating
// player, so its last items can be scrolled clear of it.
const double kFloatingPlayerClearance = 136;

// The wide layout's compact player, floating above the bottom of the window
// in place of the mini player and full-screen Now Playing view: track info
// and small transport controls on one line, a short progress bar beneath.
class FloatingPlayer extends StatelessWidget {
  final AbstractPlayerService? playerService;
  // Clicking the artwork or track info (e.g. to show the playing release).
  final VoidCallback? onInfoTap;

  const FloatingPlayer({super.key, this.playerService, this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    final svc = playerService ?? PlayerService.instance;

    // Both stream builders stay in the tree unconditionally, for the same
    // reason as MiniPlayer: the player (and its spinner) must appear on
    // either stream firing first, including a download wait before any
    // source loads.
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
            final isWaiting = waitingSnap.data ?? false;

            return ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: kFloatingPlayerMaxWidth),
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      _tappable(ArtThumbnail(
                          artPath: svc.currentRelease?.artPath,
                          size: _artSize)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(child: _tappable(_info(details))),
                                const SizedBox(width: 8),
                                _controls(svc, isWaiting),
                              ],
                            ),
                            PlaybackProgress(svc: svc, compact: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Matches the height of the info/controls line plus the progress bar
  // beneath it, so the artwork fills the player's height.
  static const double _artSize = 64;

  Widget _tappable(Widget child) {
    return MouseRegion(
      cursor: onInfoTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onInfoTap,
        child: child,
      ),
    );
  }

  Widget _info(NowPlayingDetails details) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(details.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (details.album != null)
          Text(details.album!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _controls(AbstractPlayerService svc, bool isWaiting) {
    const compact = VisualDensity.compact;
    return StreamBuilder<PlayerState>(
      stream: svc.playerStateStream,
      builder: (context, stateSnap) {
        final state = stateSnap.data;
        final playing = (state?.playing ?? false) &&
            state?.processingState != ProcessingState.completed;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 22,
              visualDensity: compact,
              tooltip: 'Previous track',
              icon: const Icon(Icons.skip_previous),
              onPressed: svc.hasPrevious ? svc.seekToPrevious : null,
            ),
            if (isWaiting)
              IconButton(
                visualDensity: compact,
                tooltip: 'Cancel',
                icon: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                onPressed: svc.cancelDownloadWait,
              )
            else
              IconButton.filled(
                iconSize: 24,
                visualDensity: compact,
                tooltip: playing ? 'Pause' : 'Play',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: playing ? svc.pause : svc.play,
              ),
            IconButton(
              iconSize: 22,
              visualDensity: compact,
              tooltip: 'Next track',
              icon: const Icon(Icons.skip_next),
              onPressed: svc.hasNext ? svc.seekToNext : null,
            ),
          ],
        );
      },
    );
  }
}
