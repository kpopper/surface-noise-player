import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:surface_noise_player/screens/now_playing_screen.dart';
import '../../helpers/fake_player_service.dart';

void main() {
  testWidgets('closes itself when playback stops', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => NowPlayingScreen(playerService: fake)),
              ),
              child: const Text('Library'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Track One'), findsOneWidget);

    fake.clearSequenceState();
    await tester.pumpAndSettle();

    expect(find.text('Track One'), findsNothing);
    expect(find.text('Library'), findsOneWidget);
  });
}
