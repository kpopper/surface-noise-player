import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';

Release makeRelease(String name,
        {List<String> tags = const [], DateTime? lastActivityAt}) =>
    Release(
      folderPath: '/music/$name',
      name: name,
      tracks: const [],
      tags: tags,
      lastActivityAt: lastActivityAt,
    );

void main() {
  late FakeLibraryService fakeService;
  late FakeBookmarkService fakeBookmarks;
  late LibraryProvider provider;

  setUp(() {
    fakeService = FakeLibraryService();
    fakeBookmarks = FakeBookmarkService();
    provider = LibraryProvider(fakeService, fakeBookmarks);
  });

  tearDown(() => provider.dispose());

  group('init', () {
    test(
        'sets rootPath, syncs, and loads releases from DB when a saved root exists',
        () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [makeRelease('Album A')];

      await provider.init();

      expect(provider.rootPath, '/music');
      expect(provider.allReleases.length, 1);
      expect(provider.allReleases.first.name, 'Album A');
      expect(fakeService.syncedRoots, ['/music']);
      // Loaded once immediately (to show what's already known) and once
      // more after the sync completes.
      expect(fakeService.loadLibraryCallCount, 2);
    });

    test('shows already-known releases before the sync completes', () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [makeRelease('Already Known')];
      fakeService.syncGate = Completer<void>();

      final initFuture = provider.init();
      await Future(() {}); // let init() run up to the sync gate

      expect(provider.allReleases.map((r) => r.name), ['Already Known']);
      expect(provider.loading, isTrue);

      fakeService.syncGate!.complete();
      await initFuture;
    });

    test('shows a release as soon as syncLibrary reports progress, mid-sync',
        () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [];
      fakeService.syncGate = Completer<void>();

      final initFuture = provider.init();
      await Future(() {}); // let init() run up to the sync gate
      expect(provider.allReleases, isEmpty);

      // Simulate syncLibrary having just discovered one release.
      fakeService.releasesToReturn = [makeRelease('Newly Found')];
      fakeService.triggerProgress();
      await Future(() {}); // let the reload triggered by the tick complete

      expect(provider.allReleases.map((r) => r.name), ['Newly Found']);
      expect(provider.loading, isTrue); // sync itself hasn't finished yet

      fakeService.syncGate!.complete();
      await initFuture;
    });

    test('coalesces rapid progress ticks instead of piling up reloads',
        () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [];
      fakeService.syncGate = Completer<void>();

      final initFuture = provider.init();
      await Future(() {}); // let init() run up to the sync gate
      final countBefore = fakeService.loadLibraryCallCount;

      // Fired back-to-back within the same synchronous stack, as concurrent
      // discoveries completing near-simultaneously would.
      fakeService.triggerProgress();
      fakeService.triggerProgress();
      fakeService.triggerProgress();
      await Future(() {});

      expect(fakeService.loadLibraryCallCount - countBefore, lessThan(3));

      fakeService.syncGate!.complete();
      await initFuture;
    });

    test('leaves rootPath null and does not sync or load when no saved root',
        () async {
      fakeService.rootToReturn = null;

      await provider.init();

      expect(provider.rootPath, isNull);
      expect(provider.allReleases, isEmpty);
      expect(fakeService.syncedRoots, isEmpty);
      expect(fakeService.loadLibraryCallCount, 0);
    });

    test('uses bookmark path over saved root when both exist', () async {
      fakeBookmarks.pathToReturn = '/bookmarked';
      fakeService.rootToReturn = '/saved';
      fakeService.releasesToReturn = [];

      await provider.init();

      expect(provider.rootPath, '/bookmarked');
      expect(fakeService.syncedRoots, ['/bookmarked']);
    });
  });

  group('refresh', () {
    test('syncs and reloads releases from DB when rootPath is set', () async {
      fakeService.rootToReturn = '/music';
      await provider.init();

      fakeService.releasesToReturn = [makeRelease('New Album')];
      await provider.refresh();

      expect(provider.allReleases.first.name, 'New Album');
      expect(fakeService.syncedRoots, ['/music', '/music']);
      // init() loads twice (immediate + post-sync); refresh() loads once
      // more (post-sync only — no separate "show what's known" step, since
      // it's already showing the previous load).
      expect(fakeService.loadLibraryCallCount, 3);
    });

    test('is a no-op when rootPath is null', () async {
      await provider.refresh();
      expect(fakeService.syncedRoots, isEmpty);
      expect(fakeService.loadLibraryCallCount, 0);
    });
  });

  group('pickFolder', () {
    test('sets rootPath, syncs, and loads the new folder\'s library', () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [makeRelease('Old Album')];
      await provider.init();

      fakeService.rootToReturn = '/new-music';
      fakeService.releasesToReturn = [makeRelease('New Album')];
      await provider.pickFolder();

      expect(provider.rootPath, '/new-music');
      expect(provider.allReleases.map((r) => r.name), ['New Album']);
      expect(fakeService.syncedRoots, ['/music', '/new-music']);
    });

    test('clears active tag filters', () async {
      provider.toggleTag('jazz');
      fakeService.rootToReturn = '/new-music';
      await provider.pickFolder();
      expect(provider.activeTags, isEmpty);
    });

    test('does nothing when pickLibraryFolder returns null', () async {
      fakeService.rootToReturn = null;
      await provider.pickFolder();
      expect(provider.rootPath, isNull);
      expect(fakeService.syncedRoots, isEmpty);
    });
  });

  group('releases (tag filtering)', () {
    setUp(() async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [
        makeRelease('Jazz Album', tags: ['jazz', 'vinyl']),
        makeRelease('Rock Album', tags: ['rock']),
        makeRelease('Untagged Album'),
      ];
      await provider.init();
    });

    test('returns all releases when no tags active', () {
      expect(provider.releases.length, 3);
    });

    test('filters by a single active tag', () {
      provider.toggleTag('jazz');
      expect(provider.releases.length, 1);
      expect(provider.releases.first.name, 'Jazz Album');
    });

    test('filters by multiple active tags (AND logic)', () {
      provider.toggleTag('jazz');
      provider.toggleTag('vinyl');
      expect(provider.releases.length, 1);
      expect(provider.releases.first.name, 'Jazz Album');
    });

    test('returns empty when no release matches all active tags', () {
      provider.toggleTag('jazz');
      provider.toggleTag('rock');
      expect(provider.releases, isEmpty);
    });
  });

  group('toggleTag', () {
    test('adds a tag to activeTags', () {
      provider.toggleTag('jazz');
      expect(provider.activeTags, ['jazz']);
    });

    test('removes a tag that is already active', () {
      provider.toggleTag('jazz');
      provider.toggleTag('jazz');
      expect(provider.activeTags, isEmpty);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.toggleTag('jazz');
      expect(notifyCount, 1);
    });
  });

  group('clearTagFilter', () {
    test('removes all active tags', () {
      provider.toggleTag('jazz');
      provider.toggleTag('rock');
      provider.clearTagFilter();
      expect(provider.activeTags, isEmpty);
    });

    test('notifies listeners', () {
      provider.toggleTag('jazz');
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.clearTagFilter();
      expect(notifyCount, 1);
    });
  });

  group('addTagToRelease', () {
    late Release release;

    setUp(() async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [
        makeRelease('Album A', tags: ['jazz'])
      ];
      await provider.init();
      release = provider.allReleases.first;
    });

    test('calls the service with correct args', () async {
      await provider.addTagToRelease(release, 'vinyl');
      expect(fakeService.lastAddedTagPath, release.folderPath);
      expect(fakeService.lastAddedTag, 'vinyl');
    });

    test('updates the release in memory', () async {
      await provider.addTagToRelease(release, 'vinyl');
      expect(provider.allReleases.first.tags, containsAll(['jazz', 'vinyl']));
    });

    test('notifies listeners', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      await provider.addTagToRelease(release, 'vinyl');
      expect(notifyCount, greaterThan(0));
    });
  });

  group('removeTagFromRelease', () {
    late Release release;

    setUp(() async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [
        makeRelease('Album A', tags: ['jazz', 'vinyl'])
      ];
      await provider.init();
      release = provider.allReleases.first;
    });

    test('calls the service with correct args', () async {
      await provider.removeTagFromRelease(release, 'jazz');
      expect(fakeService.lastRemovedTagPath, release.folderPath);
      expect(fakeService.lastRemovedTag, 'jazz');
    });

    test('removes the tag from memory', () async {
      await provider.removeTagFromRelease(release, 'jazz');
      expect(provider.allReleases.first.tags, ['vinyl']);
      expect(provider.allReleases.first.tags, isNot(contains('jazz')));
    });
  });

  group('sort by recent activity', () {
    test('releases with activity appear before those without', () async {
      final t = DateTime(2025, 6, 1);
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [
        makeRelease('No Activity'),
        makeRelease('Has Activity', lastActivityAt: t),
      ];
      await provider.init();
      expect(provider.releases.first.name, 'Has Activity');
    });

    test('more recent activity sorts before older', () async {
      final older = DateTime(2025, 1, 1);
      final newer = DateTime(2025, 6, 1);
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [
        makeRelease('Older', lastActivityAt: older),
        makeRelease('Newer', lastActivityAt: newer),
      ];
      await provider.init();
      expect(provider.releases.first.name, 'Newer');
    });

    test('releases without activity sort alphabetically at the end', () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [
        makeRelease('Zebra'),
        makeRelease('Apple'),
      ];
      await provider.init();
      expect(provider.releases.map((r) => r.name).toList(), ['Apple', 'Zebra']);
    });

    test('recordPlay calls service and moves release to top', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [
        makeRelease('B', lastActivityAt: yesterday),
        makeRelease('A'),
      ];
      await provider.init();
      await provider.recordPlay('/music/A');
      expect(provider.releases.first.name, 'A');
      expect(fakeService.lastRecordedPlayPath, '/music/A');
    });
  });

  group('loading state', () {
    test('is true during load and false after', () async {
      fakeService.rootToReturn = '/music';
      final states = <bool>[];
      provider.addListener(() => states.add(provider.loading));

      await provider.init();

      expect(states, containsAllInOrder([true, false]));
    });
  });
}
