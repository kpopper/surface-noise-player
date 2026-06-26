import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/library_screen.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';

Release makeRelease(String name, {bool isAvailable = true}) => Release(
      folderPath: '/music/$name',
      name: name,
      tracks: const [],
      tags: const [],
      isAvailable: isAvailable,
    );

Widget wrapWithProvider(LibraryProvider provider) =>
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: const MaterialApp(home: LibraryScreen()),
    );

Future<LibraryProvider> pumpLibraryScreen(
  WidgetTester tester, {
  String? savedRoot,
  List<Release> releases = const [],
  List<String> tags = const [],
}) async {
  final fake = FakeLibraryService()
    ..rootToReturn = savedRoot
    ..releasesToReturn = releases
    ..tagsToReturn = tags;
  final provider = LibraryProvider(fake, FakeBookmarkService());
  await tester.pumpWidget(wrapWithProvider(provider));
  await tester.pumpAndSettle();
  return provider;
}

void main() {
  group('no folder selected', () {
    testWidgets('shows empty state prompt', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: null);
      expect(find.text('No library set up'), findsOneWidget);
      expect(find.text('Set up Library'), findsOneWidget);
    });

    testWidgets('shows manage icon button in app bar', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: null);
      expect(find.byIcon(Icons.library_add), findsWidgets);
    });
  });

  group('folder selected — no albums selected', () {
    testWidgets('shows "No albums selected" when no releases chosen', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: []);
      expect(find.textContaining('No albums selected'), findsOneWidget);
      expect(find.text('Manage Library'), findsOneWidget);
    });
  });

  group('folder selected — with releases', () {
    testWidgets('renders a card for each release', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: [
        makeRelease('Album A'),
        makeRelease('Album B'),
        makeRelease('Album C'),
      ]);
      expect(find.text('Album A'), findsOneWidget);
      expect(find.text('Album B'), findsOneWidget);
      expect(find.text('Album C'), findsOneWidget);
    });

    testWidgets('shows app bar title', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: [makeRelease('X')]);
      expect(find.text('Surface Noise'), findsOneWidget);
    });

    testWidgets('refresh button is present', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: [makeRelease('X')]);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('unavailable release is shown but non-interactive', (tester) async {
      final fake = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [makeRelease('Unavailable Album', isAvailable: false)];
      final fakeBookmarks = FakeBookmarkService()..downloadResult = false;
      final provider = LibraryProvider(fake, fakeBookmarks);
      await tester.pumpWidget(wrapWithProvider(provider));
      await tester.pumpAndSettle();

      expect(find.text('Unavailable Album'), findsOneWidget);
      await tester.tap(find.text('Unavailable Album'));
      await tester.pumpAndSettle();
      expect(find.text('Surface Noise'), findsOneWidget); // still on library screen
    });
  });

  group('tag filtering integration', () {
    testWidgets('shows "No releases match" when active filter has no results', (tester) async {
      final provider = await pumpLibraryScreen(tester,
          savedRoot: '/music',
          releases: [makeRelease('Album A')],
          tags: ['jazz']);

      provider.toggleTag('jazz'); // Album A has no tags → filtered out
      await tester.pump();

      expect(find.textContaining('No releases match'), findsOneWidget);
    });
  });
}
