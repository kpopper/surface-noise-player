import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/release.dart';
import '../services/abstract_player_service.dart';
import '../services/bookmark_service.dart';
import '../services/library_provider.dart';
import '../services/player_service.dart';
import '../utils/layout.dart';
import '../widgets/mini_player.dart';
import '../widgets/floating_player.dart';
import '../widgets/playback_shortcuts.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'release_screen.dart';

class AppShell extends StatefulWidget {
  final AbstractPlayerService? playerService;
  final BookmarkService? bookmarkService;

  const AppShell({super.key, this.playerService, this.bookmarkService});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AbstractPlayerService _svc;
  StreamSubscription<SequenceState?>? _sequenceSub;
  StreamSubscription<String>? _errorMessageSub;
  StreamSubscription<({String folderPath, Track track})>? _metadataUpdatedSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  String? _lastRecordedReleasePath;
  bool _playing = false;
  // The release shown in place of the wide layout's grid, if any.
  Release? _selectedRelease;
  // One per layout, since switching layouts swaps the search field and a
  // focus node can only be attached to one at a time.
  final _narrowSearchFocus = FocusNode();
  final _wideSearchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _svc = widget.playerService ?? PlayerService.instance;
    _sequenceSub = _svc.sequenceStateStream.listen((state) {
      final release = _svc.currentRelease;
      if (release == null) return;
      if (release.folderPath == _lastRecordedReleasePath) return;
      _lastRecordedReleasePath = release.folderPath;
      if (!mounted) return;
      context.read<LibraryProvider>().recordPlay(release.folderPath);
    });
    _errorMessageSub = _svc.errorMessageStream.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
    _playerStateSub = _svc.playerStateStream.listen((state) {
      _playing =
          state.playing && state.processingState != ProcessingState.completed;
    });
    _metadataUpdatedSub = _svc.trackMetadataUpdatedStream.listen((event) {
      if (!mounted) return;
      context
          .read<LibraryProvider>()
          .updateTrackMetadata(event.folderPath, event.track);
    });
  }

  @override
  void dispose() {
    _sequenceSub?.cancel();
    _errorMessageSub?.cancel();
    _metadataUpdatedSub?.cancel();
    _playerStateSub?.cancel();
    _narrowSearchFocus.dispose();
    _wideSearchFocus.dispose();
    super.dispose();
  }

  void _selectRelease(Release? release) =>
      setState(() => _selectedRelease = release);

  // In the wide layout the search field is only in the Library view, so an
  // open release is closed first and the field focused once it's built.
  void _focusSearch(bool wide) {
    if (!wide) {
      _narrowSearchFocus.requestFocus();
      return;
    }
    if (_selectedRelease == null) {
      _wideSearchFocus.requestFocus();
      return;
    }
    _selectRelease(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _wideSearchFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    return PlaybackShortcuts(
      svc: _svc,
      isPlaying: () => _playing,
      onFocusSearch: () => _focusSearch(wide),
      child: wide ? _buildWide() : _buildNarrow(),
    );
  }

  // Sidebar beside the cover grid (or the selected release in its place),
  // with a compact player floating centred over the bottom of the window in
  // place of the mini player and Now Playing screen.
  Widget _buildWide() {
    final selected = _selectedRelease;
    return Scaffold(
      body: Stack(
        children: [
          LibraryScreen(
            wide: true,
            onReleaseSelected: _selectRelease,
            onHome: () => _selectRelease(null),
            searchFocusNode: _wideSearchFocus,
            wideDetail: selected == null
                ? null
                : ReleaseScreen(
                    key: ValueKey(selected.folderPath),
                    release: selected,
                    playerService: _svc,
                    bookmarkService: widget.bookmarkService,
                    onClose: () => _selectRelease(null),
                    bottomPadding: kFloatingPlayerClearance,
                    wide: true,
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: kFloatingPlayerMargin,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FloatingPlayer(
                  playerService: _svc,
                  onInfoTap: () {
                    final playing = _svc.currentRelease;
                    if (playing != null) _selectRelease(playing);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrow() {
    final svc = _svc;

    return Scaffold(
      body: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => LibraryScreen(searchFocusNode: _narrowSearchFocus),
        ),
      ),
      // Both stream builders are kept unconditionally in the tree (neither
      // short-circuits to a hidden widget on its own) so each stays mounted
      // and subscribed regardless of which stream fires first — otherwise an
      // early "nothing to show" return from the outer builder would prevent
      // the inner one from ever mounting to catch a later event, and the
      // mini player (with its spinner) would never appear during a download
      // wait, since that only shows up on waitingForDownloadStream, not
      // sequenceStateStream.
      bottomNavigationBar: StreamBuilder<SequenceState?>(
        stream: svc.sequenceStateStream,
        builder: (context, snap) {
          return StreamBuilder<bool>(
            stream: svc.waitingForDownloadStream,
            initialData: svc.isWaitingForDownload,
            builder: (context, waitingSnap) {
              if (snap.data?.currentSource?.tag == null &&
                  svc.currentTrack == null) {
                return const SizedBox.shrink();
              }
              return MiniPlayer(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const NowPlayingScreen(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
