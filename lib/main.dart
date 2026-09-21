import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/app_shell.dart';
import 'services/audio_handler.dart';
import 'services/library_provider.dart';

Future<void> main() async {
  await AudioService.init(
    builder: () => SurfaceNoiseAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.yourname.surface_noise_player.audio',
      androidNotificationChannelName: 'Surface Noise Player',
      androidNotificationOngoing: true,
    ),
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
      home: const AppShell(),
    );
  }
}
