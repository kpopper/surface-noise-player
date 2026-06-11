import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/library_screen.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';

Release makeRelease(String name) => Release(
      folderPath: '/music/$name',
      name: name,
      tracks: const [],
      tags: const [],
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
      expect(find.text('No music folder selected'), findsOneWidget);
      expect(find.text('Choose folder from iCloud Drive'), findsOneWidget);
    });

    testWidgets('shows folder icon button in app bar', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: null);
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });
  });

  group('folder selected — empty library', () {
    testWidgets('shows "No releases found" when folder has no audio', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: []);
      expect(find.textContaining('No releases found'), findsOneWidget);
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
  });

  group('tag filtering integration', () {
    testWidgets('shows "No releases match" when active filter has no results', (tester) async {
      // Provider has releases but active tag filter yields nothing.
      // We toggle a tag that no release has.
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
