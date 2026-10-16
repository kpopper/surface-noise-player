import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/abstract_player_service.dart';

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _NextTrackIntent extends Intent {
  const _NextTrackIntent();
}

class _PreviousTrackIntent extends Intent {
  const _PreviousTrackIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

bool _isTyping() {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused != null &&
      (focused.widget is EditableText ||
          focused.findAncestorWidgetOfExactType<EditableText>() != null);
}

// Disabled while a text field has focus, so the key press is left unhandled
// and reaches the field instead (typing a space, moving the cursor).
class _UnlessTypingAction<T extends Intent> extends CallbackAction<T> {
  _UnlessTypingAction({required super.onInvoke});

  @override
  bool isEnabled(T intent) => !_isTyping();
}

// App-wide keyboard shortcuts: Space play/pause, ⌘←/⌘→ previous/next track,
// ⌘F to focus search.
class PlaybackShortcuts extends StatelessWidget {
  final AbstractPlayerService svc;
  // Whether playback is currently running, so Space knows which way to go.
  final bool Function() isPlaying;
  // ⌘F: focus the library search field (see AppShell).
  final VoidCallback onFocusSearch;
  final Widget child;

  const PlaybackShortcuts({
    super.key,
    required this.svc,
    required this.isPlaying,
    required this.onFocusSearch,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): _PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, meta: true):
            _NextTrackIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
            _PreviousTrackIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _FocusSearchIntent(),
      },
      child: Actions(
        actions: {
          _PlayPauseIntent: _UnlessTypingAction<_PlayPauseIntent>(
            onInvoke: (_) {
              // Mirrors the on-screen control, which is a cancel spinner
              // while a download is pending.
              if (svc.isWaitingForDownload) {
                svc.cancelDownloadWait();
              } else if (isPlaying()) {
                svc.pause();
              } else {
                svc.play();
              }
              return null;
            },
          ),
          _NextTrackIntent: _UnlessTypingAction<_NextTrackIntent>(
            onInvoke: (_) => svc.hasNext ? svc.seekToNext() : null,
          ),
          _PreviousTrackIntent: _UnlessTypingAction<_PreviousTrackIntent>(
            onInvoke: (_) => svc.hasPrevious ? svc.seekToPrevious() : null,
          ),
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              onFocusSearch();
              return null;
            },
          ),
        },
        // Keeps keyboard focus inside these shortcuts when nothing else has
        // it (e.g. on launch, or after clicking away from the search field)
        // — otherwise key presses would start above this widget and never
        // reach it.
        child: FocusScope(autofocus: true, child: child),
      ),
    );
  }
}
