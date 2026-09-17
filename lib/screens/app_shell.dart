import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/release.dart';
import '../services/abstract_player_service.dart';
import '../services/library_provider.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';

class AppShell extends StatefulWidget {
  final AbstractPlayerService? playerService;

  const AppShell({super.key, this.playerService});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AbstractPlayerService _svc;
  StreamSubscription<SequenceState?>? _sequenceSub;
  StreamSubscription<String>? _errorMessageSub;
  StreamSubscription<({String folderPath, Track track})>? _metadataUpdatedSub;
  String? _lastRecordedReleasePath;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = _svc;

    return Scaffold(
      body: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => const LibraryScreen(),
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
