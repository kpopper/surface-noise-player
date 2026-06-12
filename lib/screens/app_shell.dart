import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<SequenceState?>? _sequenceSub;
  String? _lastRecordedReleasePath;

  @override
  void initState() {
    super.initState();
    _sequenceSub = PlayerService.instance.sequenceStateStream.listen((state) {
      final release = PlayerService.instance.currentRelease;
      if (release == null) return;
      if (release.folderPath == _lastRecordedReleasePath) return;
      _lastRecordedReleasePath = release.folderPath;
      if (!mounted) return;
      context.read<LibraryProvider>().recordPlay(release.folderPath);
    });
  }

  @override
  void dispose() {
    _sequenceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = PlayerService.instance;

    return Scaffold(
      body: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => const LibraryScreen(),
        ),
      ),
      bottomNavigationBar: StreamBuilder<SequenceState?>(
        stream: svc.sequenceStateStream,
        builder: (context, snap) {
          if (snap.data?.currentSource?.tag == null) return const SizedBox.shrink();
          return MiniPlayer(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const NowPlayingScreen(),
              ),
            ),
          );
        },
      ),
    );
  }
}
