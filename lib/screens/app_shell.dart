import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

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
