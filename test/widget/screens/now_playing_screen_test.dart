import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/now_playing_screen.dart';
import '../../helpers/fake_player_service.dart';

void main() {
  testWidgets('shows the play icon once the queue finishes playing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();

    await tester
        .pumpWidget(MaterialApp(home: NowPlayingScreen(playerService: fake)));

    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    fake.emitPlayerState(
        playing: true, processingState: ProcessingState.completed);
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets(
      'appears with a spinner as soon as a track is requested, before just_audio has loaded it',
      (tester) async {
    // Regression: this screen used to only render once sequenceStateStream
    // had a loaded source, so opening it during a download wait showed a
    // blank screen instead of the buffering spinner.
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();
    final release = Release(
      folderPath: '/music/Test',
      name: 'Test',
      tracks: const [
        Track(path: '/music/Test/01.mp3', title: 'Track One', trackNumber: 1)
      ],
      tags: const [],
    );

    await tester
        .pumpWidget(MaterialApp(home: NowPlayingScreen(playerService: fake)));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Track One'), findsNothing);

    await fake.playRelease(release);
    fake.emitWaitingForDownload(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Track One'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The spinner replaces the play/pause button itself, not an overlay.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);

    fake.emitWaitingForDownload(false);
    fake.emitSequenceState(
        const MediaItem(id: '/music/Test/01.mp3', title: 'Track One'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Track One'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
