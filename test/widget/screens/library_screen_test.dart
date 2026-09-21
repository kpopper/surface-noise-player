import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/library_screen.dart';
import 'package:surface_noise_player/screens/release_screen.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';

Release makeRelease(String name, {DateTime? lastActivityAt}) => Release(
      folderPath: '/music/$name',
      name: name,
      tracks: const [],
      tags: const [],
      lastActivityAt: lastActivityAt,
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
  group('initial load', () {
    testWidgets(
        'screen is blank while the initial database load is in flight',
        (tester) async {
      final fakeBookmark = FakeBookmarkService()
        ..resolveBookmarkGate = Completer<void>();
      final fake = FakeLibraryService()
        ..rootToReturn = null
        ..releasesToReturn = [];
      final provider = LibraryProvider(fake, fakeBookmark);
      await tester.pumpWidget(wrapWithProvider(provider));
      await tester.pump();

      expect(find.text('No library set up'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      fakeBookmark.resolveBookmarkGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('No library set up'), findsOneWidget);
    });

    testWidgets(
        'shows the release list once the initial load resolves, when a root is already saved',
        (tester) async {
      final fakeBookmark = FakeBookmarkService()
        ..resolveBookmarkGate = Completer<void>();
      final fake = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [makeRelease('Album A')];
      final provider = LibraryProvider(fake, fakeBookmark);
      await tester.pumpWidget(wrapWithProvider(provider));
      await tester.pump();

      expect(find.text('Album A'), findsNothing);
      expect(find.text('No library set up'), findsNothing);

      fakeBookmark.resolveBookmarkGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Album A'), findsOneWidget);
    });
  });

  group('no folder selected', () {
    testWidgets('shows empty state prompt', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: null);
      expect(find.text('No library set up'), findsOneWidget);
      expect(find.text('Choose Library Folder'), findsOneWidget);
    });

    testWidgets('shows choose-folder icon button in app bar', (tester) async {
      await pumpLibraryScreen(tester, savedRoot: null);
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });
  });

  group('folder selected — no releases found', () {
    testWidgets('shows "No releases found" when the library is empty',
        (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: []);
      expect(find.textContaining('No releases found'), findsOneWidget);
      expect(find.text('Choose a Different Folder'), findsOneWidget);
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
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: [makeRelease('X')]);
      expect(find.text('Surface Noise'), findsOneWidget);
    });

    testWidgets('refresh button is present', (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: [makeRelease('X')]);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets(
        'tapping a release card opens the release screen regardless of download status',
        (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: [makeRelease('Album A')]);

      await tester.tap(find.text('Album A'));
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsOneWidget);
    });
  });

  group('sync spinner', () {
    testWidgets(
        'refresh icon is replaced by a spinner while a sync is in progress',
        (tester) async {
      final fake = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [makeRelease('X')];
      final provider = LibraryProvider(fake, FakeBookmarkService());
      await tester.pumpWidget(wrapWithProvider(provider));
      await tester.pumpAndSettle(); // initial sync completes

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      fake.syncGate = Completer<void>();
      final refreshFuture = provider.refresh();
      await tester.pump(); // let loading flip true and rebuild

      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      fake.syncGate!.complete();
      await refreshFuture;
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets(
        'the choose-folder button is disabled while a sync is in progress',
        (tester) async {
      final fake = FakeLibraryService()
        ..rootToReturn = '/music'
        ..releasesToReturn = [makeRelease('X')];
      final provider = LibraryProvider(fake, FakeBookmarkService());
      await tester.pumpWidget(wrapWithProvider(provider));
      await tester.pumpAndSettle();

      fake.syncGate = Completer<void>();
      final refreshFuture = provider.refresh();
      await tester.pump();

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.folder_open),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);

      fake.syncGate!.complete();
      await refreshFuture;
      await tester.pumpAndSettle();
    });
  });

  group('tag filtering integration', () {
    testWidgets('shows "No releases match" when active filter has no results',
        (tester) async {
      final provider = await pumpLibraryScreen(tester,
          savedRoot: '/music',
          releases: [makeRelease('Album A')],
          tags: ['jazz']);

      provider.toggleTag('jazz'); // Album A has no tags → filtered out
      await tester.pump();

      expect(find.textContaining('No releases match'), findsOneWidget);
    });
  });

  group('search filtering', () {
    testWidgets('typing in the search field filters releases by name',
        (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: [
        makeRelease('Aardvark'),
        makeRelease('Bumblebee'),
      ]);

      expect(find.text('Aardvark'), findsOneWidget);
      expect(find.text('Bumblebee'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bumble');
      await tester.pump();

      expect(find.text('Aardvark'), findsNothing);
      expect(find.text('Bumblebee'), findsOneWidget);
    });

    testWidgets('clearing the search field restores the full list',
        (tester) async {
      await pumpLibraryScreen(tester, savedRoot: '/music', releases: [
        makeRelease('Aardvark'),
        makeRelease('Bumblebee'),
      ]);

      await tester.enterText(find.byType(TextField), 'bumble');
      await tester.pump();
      expect(find.text('Aardvark'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.text('Aardvark'), findsOneWidget);
      expect(find.text('Bumblebee'), findsOneWidget);
    });

    testWidgets('search with no matches shows "No releases match"',
        (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: [makeRelease('Aardvark')]);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();

      expect(find.textContaining('No releases match'), findsOneWidget);
    });
  });

  group('keyboard dismissal', () {
    testWidgets('tapping outside the search field dismisses the keyboard',
        (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: [makeRelease('Album A')]);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // Tap blank space within the list's viewport, well below the single
      // short release card, rather than on any interactive widget.
      final listBottomLeft = tester.getBottomLeft(find.byType(ListView));
      await tester.tapAt(listBottomLeft + const Offset(50, -20));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('scrolling the release list dismisses the keyboard',
        (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music',
          releases: [for (var i = 0; i < 20; i++) makeRelease('Album $i')]);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });
  });

  group('sort toggle', () {
    // Apple is older but alphabetically first; Zebra is more recent but
    // alphabetically last — recency and alphabetical order disagree, so
    // these tests can tell the two modes apart.
    List<Release> testReleases() => [
          makeRelease('Apple', lastActivityAt: DateTime(2025, 1, 1)),
          makeRelease('Zebra', lastActivityAt: DateTime(2025, 6, 1)),
        ];

    List<String?> visibleNames(WidgetTester tester) => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();

    testWidgets('defaults to recency order with a recency icon shown',
        (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: testReleases());

      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
      expect(visibleNames(tester), ['Zebra', 'Apple']);
    });

    testWidgets('tapping the toggle switches to alphabetical order',
        (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: testReleases());

      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pump();

      expect(find.byIcon(Icons.sort_by_alpha), findsOneWidget);
      expect(visibleNames(tester), ['Apple', 'Zebra']);
    });

    testWidgets('tapping the toggle twice returns to recency order',
        (tester) async {
      await pumpLibraryScreen(tester,
          savedRoot: '/music', releases: testReleases());

      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.sort_by_alpha));
      await tester.pump();

      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
      expect(visibleNames(tester), ['Zebra', 'Apple']);
    });
  });
}
