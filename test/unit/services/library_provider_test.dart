import 'package:flutter_test/flutter_test.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';

Release makeRelease(String name, {List<String> tags = const [], DateTime? lastActivityAt}) => Release(
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
    test('sets rootPath and quick-scans when a saved root exists', () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [makeRelease('Album A')];

      await provider.init();

      expect(provider.rootPath, '/music');
      expect(provider.allReleases.length, 1);
      expect(provider.allReleases.first.name, 'Album A');
      expect(fakeService.quickScanCallCount, 1);
      expect(fakeService.scanCallCount, 0);
    });

    test('leaves rootPath null and does not scan when no saved root', () async {
      fakeService.rootToReturn = null;

      await provider.init();

      expect(provider.rootPath, isNull);
      expect(provider.allReleases, isEmpty);
      expect(fakeService.quickScanCallCount, 0);
      expect(fakeService.scanCallCount, 0);
    });
  });

  group('refresh', () {
    test('quick-scans when rootPath is set', () async {
      fakeService.rootToReturn = '/music';
      await provider.init();

      fakeService.releasesToReturn = [makeRelease('New Album')];
      await provider.refresh();

      expect(provider.allReleases.first.name, 'New Album');
      expect(fakeService.quickScanCallCount, 2);
      expect(fakeService.scanCallCount, 0);
    });

    test('is a no-op when rootPath is null', () async {
      await provider.refresh();
      expect(fakeService.quickScanCallCount, 0);
      expect(fakeService.scanCallCount, 0);
    });
  });

  group('pickFolder', () {
    test('runs a full scan (not quick scan) when a folder is picked', () async {
      fakeService.rootToReturn = '/music';
      fakeService.releasesToReturn = [makeRelease('Album A')];

      await provider.pickFolder();

      expect(fakeService.scanCallCount, 1);
      expect(fakeService.quickScanCallCount, 0);
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
      fakeService.releasesToReturn = [makeRelease('Album A', tags: ['jazz'])];
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
      fakeService.releasesToReturn = [makeRelease('Album A', tags: ['jazz', 'vinyl'])];
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
    test('is true during scan and false after', () async {
      fakeService.rootToReturn = '/music';
      final states = <bool>[];
      provider.addListener(() => states.add(provider.loading));

      await provider.init();

      expect(states, containsAllInOrder([true, false]));
    });
  });
}
