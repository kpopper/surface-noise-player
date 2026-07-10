import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:surface_noise_player/screens/now_playing_screen.dart';
import '../../helpers/fake_player_service.dart';

void main() {
  testWidgets('shows the play icon once the queue finishes playing', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();

    await tester.pumpWidget(MaterialApp(home: NowPlayingScreen(playerService: fake)));

    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    fake.emitPlayerState(playing: true, processingState: ProcessingState.completed);
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });
}
