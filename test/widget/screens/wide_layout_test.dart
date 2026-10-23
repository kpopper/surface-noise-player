import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/app_shell.dart';
import 'package:surface_noise_player/screens/library_screen.dart';
import 'package:surface_noise_player/screens/release_screen.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import 'package:surface_noise_player/widgets/mini_player.dart';
import 'package:surface_noise_player/widgets/art_thumbnail.dart';
import 'package:surface_noise_player/widgets/floating_player.dart';
import 'package:surface_noise_player/widgets/release_card.dart';
import 'package:surface_noise_player/widgets/release_grid_tile.dart';
import 'package:surface_noise_player/widgets/tag_sidebar_list.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';
import '../../helpers/fake_player_service.dart';

const wideSize = Size(1280, 800);
const narrowSize = Size(899, 800);

Release makeRelease(String name, {List<String> tags = const []}) => Release(
      folderPath: '/music/$name',
      name: name,
      tracks: [
        Track(path: '/music/$name/01.mp3', title: '$name One', trackNumber: 1),
        Track(path: '/music/$name/02.mp3', title: '$name Two', trackNumber: 2),
      ],
      tags: tags,
    );

class Harness {
  final LibraryProvider provider;
  final FakeLibraryService library;
  final FakePlayerService player;
  Harness(this.provider, this.library, this.player);
}

void setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

Future<Harness> pumpShell(
  WidgetTester tester, {
  List<Release>? releases,
  List<String> tags = const [],
  Size size = wideSize,
}) async {
  setWindowSize(tester, size);
  addTearDown(tester.view.reset);
  final library = FakeLibraryService()
    ..rootToReturn = '/music'
    ..releasesToReturn =
        releases ?? [makeRelease('Album A'), makeRelease('Album B')]
    ..tagsToReturn = tags;
  final player = FakePlayerService();
  final provider = LibraryProvider(library, FakeBookmarkService());
  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        home: AppShell(
          playerService: player,
          bookmarkService: FakeBookmarkService(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(provider, library, player);
}

Finder inGrid(String text) => find.descendant(
    of: find.byType(ReleaseGridTile), matching: find.text(text));

Finder inPlayer(String text) =>
    find.descendant(of: find.byType(FloatingPlayer), matching: find.text(text));

Future<void> startPlaying(Harness h, Release release) async {
  await h.player.playRelease(release);
  h.player.emitSequenceState(MediaItem(
    id: release.tracks.first.path,
    title: release.tracks.first.title,
    album: release.name,
  ));
}

void main() {
  group('layout switch', () {
    testWidgets('uses the sidebar and cover grid when at least 900 wide',
        (tester) async {
      await pumpShell(tester);

      expect(find.byType(ReleaseGridTile), findsNWidgets(2));
      expect(find.byType(TagSidebarList), findsOneWidget);
      expect(find.byType(ReleaseCard), findsNothing);
    });

    testWidgets('keeps the phone list layout below 900 wide', (tester) async {
      await pumpShell(tester, size: narrowSize);

      expect(find.byType(ReleaseCard), findsNWidgets(2));
      expect(find.byType(ReleaseGridTile), findsNothing);
    });

    testWidgets(
        'resizing across the breakpoint does not re-run the initial load or sync',
        (tester) async {
      final h = await pumpShell(tester);

      setWindowSize(tester, narrowSize);
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseCard), findsNWidgets(2));

      setWindowSize(tester, wideSize);
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseGridTile), findsNWidgets(2));

      expect(h.library.syncedRoots, ['/music']);
    });
  });

  group('window structure', () {
    Finder sidebar() => find
        .ancestor(
            of: find.byType(TagSidebarList), matching: find.byType(Material))
        .first;
    Finder navBarWith(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(AppBar));

    testWidgets('the sidebar runs the full height of the window',
        (tester) async {
      await pumpShell(tester);

      final rect = tester.getRect(sidebar());
      expect(rect.top, 0);
      expect(rect.bottom, wideSize.height);
    });

    testWidgets(
        'the Library nav bar sits over the main panel with search, sort, folder and refresh',
        (tester) async {
      await pumpShell(tester);

      final bar = navBarWith('Library');
      expect(bar, findsOneWidget);
      expect(tester.getRect(bar).left,
          greaterThanOrEqualTo(tester.getRect(sidebar()).right));
      expect(find.descendant(of: bar, matching: find.byType(TextField)),
          findsOneWidget);
      expect(find.descendant(of: sidebar(), matching: find.byType(TextField)),
          findsNothing);
      final search = find.descendant(of: bar, matching: find.byType(TextField));
      expect(tester.getSize(search).height, lessThanOrEqualTo(36));
      expect(tester.widget<TextField>(search).style?.fontSize, 13);
      for (final tooltip in [
        'Sorted by recent activity — tap to sort alphabetically',
        'Choose library folder',
        'Refresh library',
      ]) {
        expect(find.descendant(of: bar, matching: find.byTooltip(tooltip)),
            findsOneWidget);
      }
    });

    testWidgets('opening a release replaces the Library nav bar with its own',
        (tester) async {
      await pumpShell(tester);

      await tester.tap(inGrid('Album A'));
      await tester.pumpAndSettle();

      expect(navBarWith('Library'), findsNothing);
      expect(find.byTooltip('Refresh library'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Back to library'), findsOneWidget);
      expect(find.byTooltip('Rescan metadata'), findsOneWidget);
    });
  });

  group('grid', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'tiles fit their text without overflowing at text scale $scale',
          (tester) async {
        setWindowSize(tester, wideSize);
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpShell(tester, releases: [
          makeRelease('A Very Long Release Name That Wraps Onto Several Lines',
              tags: ['jazz', 'ambient', 'late night']),
          makeRelease('Album B'),
        ]);

        expect(find.byType(ReleaseGridTile), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('sidebar', () {
    testWidgets('says there are no tags when there are none', (tester) async {
      await pumpShell(tester);

      expect(find.text('No tags yet'), findsOneWidget);
    });

    testWidgets('displays an untagged chip', (tester) async {
      await pumpShell(
        tester,
        releases: [
          makeRelease('Album A', tags: ['jazz']),
          makeRelease('Album B'),
        ],
        tags: ['jazz'],
      );

      Finder inSidebar(String text) => find.descendant(
          of: find.byType(TagSidebarList), matching: find.text(text));

      expect(inSidebar('jazz'), findsOneWidget);
      expect(inSidebar('untagged'), findsOneWidget);
    });

    testWidgets('clicking a tag filters the grid, and clicking again clears it',
        (tester) async {
      final h = await pumpShell(
        tester,
        releases: [
          makeRelease('Album A', tags: ['jazz']),
          makeRelease('Album B'),
        ],
        tags: ['jazz'],
      );
      final sidebarTag = find.descendant(
          of: find.byType(TagSidebarList), matching: find.text('jazz'));

      await tester.tap(sidebarTag);
      await tester.pumpAndSettle();

      expect(h.provider.activeTags, ['jazz']);
      expect(find.byType(ReleaseGridTile), findsOneWidget);
      expect(inGrid('Album A'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
                find.ancestor(of: sidebarTag, matching: find.byType(ListTile)))
            .selected,
        isTrue,
      );

      await tester.tap(sidebarTag);
      await tester.pumpAndSettle();

      expect(h.provider.activeTags, isEmpty);
      expect(find.byType(ReleaseGridTile), findsNWidgets(2));
    });

    testWidgets(
        'clicking untagged tag filters the grid, and clicking again clears it',
        (tester) async {
      await pumpShell(
        tester,
        releases: [
          makeRelease('Album A', tags: ['jazz']),
          makeRelease('Album B'),
        ],
        tags: ['jazz'],
      );
      final sidebarTag = find.descendant(
          of: find.byType(TagSidebarList), matching: find.text('untagged'));

      await tester.tap(sidebarTag);
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseGridTile), findsOneWidget);
      expect(inGrid('Album B'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
                find.ancestor(of: sidebarTag, matching: find.byType(ListTile)))
            .selected,
        isTrue,
      );
      expect(inGrid('jazz'), findsNothing);

      await tester.tap(sidebarTag);
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseGridTile), findsNWidgets(2));
    });
  });

  group('release view', () {
    Finder homeTile() =>
        find.ancestor(of: find.text('Home'), matching: find.byType(ListTile));

    Future<void> openRelease(WidgetTester tester, String name) async {
      await tester.tap(inGrid(name));
      await tester.pumpAndSettle();
    }

    testWidgets('clicking a tile shows the release in place of the grid',
        (tester) async {
      await pumpShell(tester);

      await openRelease(tester, 'Album A');

      expect(find.byType(ReleaseScreen), findsOneWidget);
      expect(find.text('Album A One'), findsOneWidget);
      expect(find.byType(ReleaseGridTile), findsNothing);
      expect(find.byType(TagSidebarList), findsOneWidget);
      expect(tester.widget<ListTile>(homeTile()).selected, isFalse);
    });

    testWidgets(
        'shows the artwork in the left half and title, artist, tags and tracks in the right half',
        (tester) async {
      await pumpShell(tester, releases: [
        const Release(
          folderPath: '/music/Tagged',
          name: 'Some Artist - Some Album',
          albumArtist: 'Some Artist',
          albumTitle: 'Some Album',
          tracks: [
            Track(path: '/music/Tagged/01.mp3', title: 'First', trackNumber: 1),
          ],
          tags: ['jazz'],
        ),
      ]);
      await openRelease(tester, 'Some Artist - Some Album');

      final view = find.byType(ReleaseScreen);
      const mainLeft = kLibrarySidebarWidth + 1;
      const middle = (mainLeft + 1280) / 2;
      final art = tester.getRect(
          find.descendant(of: view, matching: find.byType(AspectRatio)));
      expect(art.width, art.height);
      expect(art.left, greaterThan(mainLeft));
      expect(art.right, lessThanOrEqualTo(middle));

      for (final text in ['Some Album', 'Some Artist', 'jazz', 'First']) {
        expect(
            tester
                .getRect(find.descendant(of: view, matching: find.text(text)))
                .left,
            greaterThanOrEqualTo(middle),
            reason: text);
      }
      expect(
          tester
              .getRect(find.descendant(of: view, matching: find.text('jazz')))
              .top,
          lessThan(tester
              .getRect(find.descendant(of: view, matching: find.text('First')))
              .top));
    });

    testWidgets('the artwork and track list scroll together as one view',
        (tester) async {
      await pumpShell(tester);
      await openRelease(tester, 'Album A');

      final list = find.descendant(
          of: find.byType(ReleaseScreen), matching: find.byType(ListView));
      expect(list, findsOneWidget);
      expect(find.descendant(of: list, matching: find.byType(AspectRatio)),
          findsOneWidget);
      expect(find.descendant(of: list, matching: find.text('Album A One')),
          findsOneWidget);
    });

    testWidgets('Home is highlighted while the grid is showing',
        (tester) async {
      await pumpShell(tester);

      expect(tester.widget<ListTile>(homeTile()).selected, isTrue);
    });

    testWidgets('tapping a track plays it', (tester) async {
      final h = await pumpShell(tester);
      await openRelease(tester, 'Album B');

      await tester.tap(find.text('Album B Two'));
      await tester.pump();

      expect(h.player.lastPlayedRelease?.folderPath, '/music/Album B');
      expect(h.player.lastPlayedTrackIndex, 1);
    });

    testWidgets('the back button returns to the grid', (tester) async {
      await pumpShell(tester);
      await openRelease(tester, 'Album A');

      await tester.tap(find.byTooltip('Back to library'));
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsNothing);
      expect(find.byType(ReleaseGridTile), findsNWidgets(2));
    });

    testWidgets('the Home item returns to the grid', (tester) async {
      await pumpShell(tester);
      await openRelease(tester, 'Album A');

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsNothing);
      expect(find.byType(ReleaseGridTile), findsNWidgets(2));
      expect(tester.widget<ListTile>(homeTile()).selected, isTrue);
    });

    testWidgets('clicking a sidebar tag returns to the filtered grid',
        (tester) async {
      await pumpShell(
        tester,
        releases: [
          makeRelease('Album A', tags: ['jazz']),
          makeRelease('Album B'),
        ],
        tags: ['jazz'],
      );
      await openRelease(tester, 'Album B');

      await tester.tap(find.descendant(
          of: find.byType(TagSidebarList), matching: find.text('jazz')));
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsNothing);
      expect(find.byType(ReleaseGridTile), findsOneWidget);
      expect(inGrid('Album A'), findsOneWidget);
    });

    testWidgets('returning to the grid keeps its scroll position',
        (tester) async {
      await pumpShell(tester, releases: [
        for (var i = 0; i < 60; i++) makeRelease('Album $i'),
      ]);
      ScrollPosition gridPosition() => tester
          .state<ScrollableState>(find.descendant(
              of: find.byType(GridView), matching: find.byType(Scrollable)))
          .position;

      await tester.drag(find.byType(GridView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      final scrolledTo = gridPosition().pixels;
      expect(scrolledTo, greaterThan(0));

      await tester.tap(find.byType(ReleaseGridTile).hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseScreen), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(gridPosition().pixels, scrolledTo);
    });

    testWidgets('returns to the grid when its release is removed',
        (tester) async {
      final h = await pumpShell(tester);
      await openRelease(tester, 'Album A');

      h.library.releasesToReturn = [makeRelease('Album B')];
      await h.provider.refresh();
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsNothing);
      expect(find.byType(ReleaseGridTile), findsOneWidget);
    });

    testWidgets(
        'the grid, tag list and track list leave room to scroll clear of the floating player',
        (tester) async {
      await pumpShell(tester, tags: ['jazz']);
      expect(tester.widget<GridView>(find.byType(GridView)).padding?.vertical,
          greaterThanOrEqualTo(kFloatingPlayerClearance));
      final tagList = tester.widget<ListView>(find.descendant(
          of: find.byType(TagSidebarList), matching: find.byType(ListView)));
      expect(tagList.padding?.vertical,
          greaterThanOrEqualTo(kFloatingPlayerClearance));

      await openRelease(tester, 'Album A');
      final list = tester.widget<ListView>(find.descendant(
          of: find.byType(ReleaseScreen), matching: find.byType(ListView)));
      expect(list.padding?.vertical,
          greaterThanOrEqualTo(kFloatingPlayerClearance));
    });
  });

  group('right-click menu', () {
    testWidgets('offers Add tag… and Rescan metadata', (tester) async {
      await pumpShell(tester);

      await tester.tap(inGrid('Album A'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Add tag…'), findsOneWidget);
      expect(find.text('Rescan metadata'), findsOneWidget);
    });

    testWidgets('Rescan metadata rescans that release', (tester) async {
      final h = await pumpShell(tester);

      await tester.tap(inGrid('Album B'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rescan metadata'));
      await tester.pumpAndSettle();

      expect(h.library.lastRescannedFolderPath, '/music/Album B');
    });

    testWidgets('Add tag… opens a dialog rather than a bottom sheet',
        (tester) async {
      final h = await pumpShell(tester);

      await tester.tap(inGrid('Album A'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add tag…'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          ' Ambient ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(h.library.lastAddedTagPath, '/music/Album A');
      expect(h.library.lastAddedTag, 'ambient');
    });
  });

  group('floating player', () {
    testWidgets('is hidden while nothing is playing', (tester) async {
      await pumpShell(tester);

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets(
        'shows the playing track with a progress bar, in place of the mini player',
        (tester) async {
      final h = await pumpShell(tester);

      await startPlaying(h, makeRelease('Album A'));
      await tester.pumpAndSettle();

      expect(inPlayer('Album A One'), findsOneWidget);
      expect(inPlayer('Album A'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(FloatingPlayer), matching: find.byType(Slider)),
          findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets(
        'floats above the bottom of the window, centred across the whole window',
        (tester) async {
      final h = await pumpShell(tester);
      await startPlaying(h, makeRelease('Album A'));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find
          .descendant(
              of: find.byType(FloatingPlayer), matching: find.byType(Material))
          .first);
      expect(rect.center.dx, moreOrLessEquals(wideSize.width / 2, epsilon: 1));
      expect(rect.bottom, wideSize.height - kFloatingPlayerMargin);
      expect(rect.width, lessThanOrEqualTo(kFloatingPlayerMaxWidth));
    });

    testWidgets('shows the artwork at the full height of the player',
        (tester) async {
      final h = await pumpShell(tester);
      await startPlaying(h, makeRelease('Album A'));
      await tester.pumpAndSettle();

      final art = tester.getSize(find.descendant(
          of: find.byType(FloatingPlayer),
          matching: find.byType(ArtThumbnail)));
      final controlsAndProgress = tester.getSize(find
          .ancestor(of: find.byType(Slider), matching: find.byType(Column))
          .first);
      expect(art.height, greaterThanOrEqualTo(controlsAndProgress.height));
    });

    testWidgets('the progress bar does not shift as the elapsed time changes',
        (tester) async {
      final h = await pumpShell(tester);
      await startPlaying(h, makeRelease('Album A'));
      await tester.pumpAndSettle();
      h.player.emitDuration(const Duration(minutes: 12));
      await tester.pump();
      final slider = find.descendant(
          of: find.byType(FloatingPlayer), matching: find.byType(Slider));

      h.player.emitPosition(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump();
      final atFiveSeconds = tester.getRect(slider);

      h.player.emitPosition(const Duration(minutes: 10, seconds: 5));
      await tester.pump();
      await tester.pump();

      expect(find.text('10:05'), findsOneWidget);
      expect(tester.getRect(slider), atFiveSeconds);
    });

    for (final (label, duration, position, elapsedText, totalText) in [
      (
        'under an hour',
        const Duration(minutes: 4, seconds: 5),
        const Duration(minutes: 1, seconds: 7),
        '1:07',
        '4:05'
      ),
      (
        'an hour or longer',
        const Duration(hours: 1, minutes: 2, seconds: 45),
        const Duration(minutes: 5, seconds: 30),
        '0:05:30',
        '1:02:45'
      ),
    ]) {
      testWidgets('shows times for a track $label as $elapsedText / $totalText',
          (tester) async {
        final h = await pumpShell(tester);
        await startPlaying(h, makeRelease('Album A'));
        await tester.pumpAndSettle();

        h.player.emitDuration(duration);
        await tester.pump();
        h.player.emitPosition(position);
        await tester.pump();
        await tester.pump();

        expect(inPlayer(elapsedText), findsOneWidget);
        expect(inPlayer(totalText), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('clicking the artwork shows the playing release',
        (tester) async {
      final h = await pumpShell(tester);
      await startPlaying(h, makeRelease('Album B'));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byType(FloatingPlayer),
          matching: find.byType(ArtThumbnail)));
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsOneWidget);
    });

    testWidgets('clicking the track info shows the playing release',
        (tester) async {
      final h = await pumpShell(tester);
      await startPlaying(h, makeRelease('Album B'));
      await tester.pumpAndSettle();

      await tester.tap(inPlayer('Album B One'));
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsOneWidget);
      expect(
          tester.widget<ReleaseScreen>(find.byType(ReleaseScreen)).release.name,
          'Album B');
    });

    testWidgets('shows a cancel spinner while waiting for a download',
        (tester) async {
      final h = await pumpShell(tester);
      await startPlaying(h, makeRelease('Album A'));
      h.player.emitWaitingForDownload(true);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.descendant(
          of: find.byType(FloatingPlayer), matching: find.byTooltip('Cancel')));
      await tester.pump();

      expect(h.player.cancelDownloadWaitCalled, isTrue);
    });
  });

  group('keyboard shortcuts', () {
    Future<void> pressWithMeta(
        WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    testWidgets('Space pauses while playing and plays while paused',
        (tester) async {
      final h = await pumpShell(tester);

      h.player.emitPlayerState(playing: true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(h.player.pauseCalled, isTrue);
      expect(h.player.playCalled, isFalse);

      h.player.emitPlayerState(playing: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(h.player.playCalled, isTrue);
    });

    testWidgets('Space cancels a pending download wait', (tester) async {
      final h = await pumpShell(tester);
      h.player.emitWaitingForDownload(true);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);

      expect(h.player.cancelDownloadWaitCalled, isTrue);
      expect(h.player.playCalled, isFalse);
    });

    testWidgets(
        'Space types into the search field instead of toggling playback',
        (tester) async {
      final h = await pumpShell(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);

      expect(h.player.playCalled, isFalse);
      expect(h.player.pauseCalled, isFalse);
    });

    testWidgets('⌘→ and ⌘← skip only when next/previous are available',
        (tester) async {
      final h = await pumpShell(tester);

      await pressWithMeta(tester, LogicalKeyboardKey.arrowRight);
      await pressWithMeta(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.player.seekToNextCallCount, 0);
      expect(h.player.seekToPreviousCallCount, 0);

      h.player
        ..hasNext = true
        ..hasPrevious = true;
      await pressWithMeta(tester, LogicalKeyboardKey.arrowRight);
      await pressWithMeta(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.player.seekToNextCallCount, 1);
      expect(h.player.seekToPreviousCallCount, 1);
    });

    testWidgets(
        '⌘F with a release showing returns to the Library view and focuses search',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(inGrid('Album A'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      await pressWithMeta(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseScreen), findsNothing);
      expect(find.byType(ReleaseGridTile), findsNWidgets(2));
      expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          isTrue);
    });

    for (final (label, size) in [('wide', wideSize), ('narrow', narrowSize)]) {
      testWidgets('⌘F focuses the search field ($label layout)',
          (tester) async {
        await pumpShell(tester, size: size);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.focusNode!.hasFocus, isFalse);

        await pressWithMeta(tester, LogicalKeyboardKey.keyF);

        expect(field.focusNode!.hasFocus, isTrue);
      });
    }
  });
}
