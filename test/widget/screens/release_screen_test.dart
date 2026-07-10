import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/release_screen.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_player_service.dart';

void main() {
  testWidgets('unavailable tracks are greyed out and cannot be tapped to play', (tester) async {
    final release = Release(
      folderPath: '/music/Test',
      name: 'Test',
      tracks: const [
        Track(path: '/music/Test/01.mp3', title: 'Track One', trackNumber: 1),
        Track(path: '/music/Test/02.mp3', title: 'Track Two', trackNumber: 2),
      ],
      tags: const [],
    );
    final fakePlayer = FakePlayerService();
    final fakeBookmarks = FakeBookmarkService()
      ..unavailablePaths = {'/music/Test/02.mp3'};

    await tester.pumpWidget(MaterialApp(
      home: ReleaseScreen(
        release: release,
        playerService: fakePlayer,
        bookmarkService: fakeBookmarks,
      ),
    ));
    await tester.pumpAndSettle();

    final unavailableTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Track Two'), matching: find.byType(ListTile)),
    );
    expect(unavailableTile.enabled, isFalse);
    expect(unavailableTile.onTap, isNull);

    await tester.tap(find.text('Track Two'));
    await tester.pump();
    expect(fakePlayer.lastPlayedTrackIndex, isNull);

    await tester.tap(find.text('Track One'));
    await tester.pump();
    expect(fakePlayer.lastPlayedTrackIndex, 0);
  });
}
