import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'screens/library_screen.dart';
import 'services/library_provider.dart';

Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.yourname.surface_noise_player.audio',
    androidNotificationChannelName: 'Surface Noise Player',
    androidNotificationOngoing: true,
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => LibraryProvider(),
      child: const SurfaceNoiseApp(),
    ),
  );
}

class SurfaceNoiseApp extends StatelessWidget {
  const SurfaceNoiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Surface Noise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}
