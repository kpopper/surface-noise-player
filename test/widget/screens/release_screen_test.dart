import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/release_screen.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';
import '../../helpers/fake_player_service.dart';

Future<LibraryProvider> makeProvider(FakeLibraryService fakeService) async {
  final provider = LibraryProvider(fakeService, FakeBookmarkService());
  await provider.init();
  return provider;
}

void main() {
  group('unavailable tracks', () {
    testWidgets('shows a cloud icon but can still be tapped to play',
        (tester) async {
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
      final fakeService = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [release];
      final provider = await makeProvider(fakeService);

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryProvider>.value(
          value: provider,
          child: MaterialApp(
            home: ReleaseScreen(
              release: release,
              playerService: fakePlayer,
              bookmarkService: fakeBookmarks,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final unavailableTile = tester.widget<ListTile>(
        find.ancestor(
            of: find.text('Track Two'), matching: find.byType(ListTile)),
      );
      expect(unavailableTile.enabled, isTrue);
      expect(unavailableTile.onTap, isNotNull);
      expect(
        find.descendant(
          of: find.byWidget(unavailableTile),
          matching: find.byIcon(Icons.cloud_download_outlined),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Track Two'));
      await tester.pump();
      expect(fakePlayer.lastPlayedTrackIndex, 1);

      await tester.tap(find.text('Track One'));
      await tester.pump();
      expect(fakePlayer.lastPlayedTrackIndex, 0);
    });
  });

  group('live updates', () {
    testWidgets('reflects updated release data without remounting',
        (tester) async {
      final initial = Release(
          folderPath: '/music/Test',
          name: 'Old Name',
          tracks: const [],
          tags: const []);
      final fakeService = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [initial];
      final provider = await makeProvider(fakeService);

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryProvider>.value(
          value: provider,
          child: MaterialApp(home: ReleaseScreen(release: initial)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old Name'), findsOneWidget);

      fakeService.releasesToReturn = [
        Release(
            folderPath: '/music/Test',
            name: 'New Name',
            tracks: const [],
            tags: const []),
      ];
      await provider.refresh();
      await tester.pumpAndSettle();

      expect(find.text('New Name'), findsOneWidget);
      expect(find.text('Old Name'), findsNothing);
    });

    testWidgets(
        'hides the track list and Play all button when there are no tracks yet',
        (tester) async {
      final release = Release(
          folderPath: '/music/Test',
          name: 'Test',
          tracks: const [],
          tags: const []);
      final fakeService = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [release];
      final provider = await makeProvider(fakeService);

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryProvider>.value(
          value: provider,
          child: MaterialApp(home: ReleaseScreen(release: release)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No tracks found yet'), findsOneWidget);
      expect(find.text('Play all'), findsNothing);
    });

    testWidgets('shows the track list and Play all button once tracks appear',
        (tester) async {
      final release = Release(
          folderPath: '/music/Test',
          name: 'Test',
          tracks: const [],
          tags: const []);
      final fakeService = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [release];
      final provider = await makeProvider(fakeService);

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryProvider>.value(
          value: provider,
          child: MaterialApp(home: ReleaseScreen(release: release)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Play all'), findsNothing);

      fakeService.releasesToReturn = [
        Release(
          folderPath: '/music/Test',
          name: 'Test',
          tracks: const [
            Track(
                path: '/music/Test/01.mp3', title: 'Track One', trackNumber: 1),
          ],
          tags: const [],
        ),
      ];
      await provider.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Track One'), findsOneWidget);
      expect(find.text('Play all'), findsOneWidget);
    });
  });

  group('auto-close', () {
    testWidgets('closes itself when the release is removed from the library',
        (tester) async {
      final release = Release(
          folderPath: '/music/Test',
          name: 'Test',
          tracks: const [],
          tags: const []);
      final fakeService = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [release];
      final provider = await makeProvider(fakeService);

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ReleaseScreen(release: release)),
                    ),
                    child: const Text('Library'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Test'), findsOneWidget);

      fakeService.releasesToReturn = [];
      await provider.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget); // back on the base screen
      expect(find.widgetWithText(AppBar, 'Test'), findsNothing);
    });
  });
}
