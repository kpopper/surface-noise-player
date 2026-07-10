import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _sequenceSub?.cancel();
    _errorMessageSub?.cancel();
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
