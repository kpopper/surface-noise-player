import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService db;

  setUp(() {
    db = DatabaseService.forTest(inMemoryDatabasePath);
  });

  tearDown(() async {
    await db.closeForTest();
  });

  group('tags', () {
    const path = '/music/album';

    test('returns empty list when no tags exist', () async {
      expect(await db.tagsForRelease(path), isEmpty);
    });

    test('addTag persists a tag', () async {
      await db.addTag(path, 'jazz');
      expect(await db.tagsForRelease(path), ['jazz']);
    });

    test('addTag is idempotent (no duplicate)', () async {
      await db.addTag(path, 'jazz');
      await db.addTag(path, 'jazz');
      expect(await db.tagsForRelease(path), ['jazz']);
    });

    test('addTag stores multiple distinct tags', () async {
      await db.addTag(path, 'jazz');
      await db.addTag(path, 'vinyl');
      final tags = await db.tagsForRelease(path);
      expect(tags, containsAll(['jazz', 'vinyl']));
      expect(tags.length, 2);
    });

    test('tags are scoped to folderPath', () async {
      await db.addTag(path, 'jazz');
      await db.addTag('/other/album', 'rock');
      expect(await db.tagsForRelease(path), ['jazz']);
      expect(await db.tagsForRelease('/other/album'), ['rock']);
    });

    test('removeTag deletes a tag', () async {
      await db.addTag(path, 'jazz');
      await db.addTag(path, 'vinyl');
      await db.removeTag(path, 'jazz');
      expect(await db.tagsForRelease(path), ['vinyl']);
    });

    test('removeTag on non-existent tag is a no-op', () async {
      await db.addTag(path, 'jazz');
      await db.removeTag(path, 'rock');
      expect(await db.tagsForRelease(path), ['jazz']);
    });

    test('allTags returns distinct tags sorted alphabetically', () async {
      await db.addTag(path, 'vinyl');
      await db.addTag(path, 'jazz');
      await db.addTag('/other', 'jazz'); // duplicate across paths
      final all = await db.allTags();
      expect(all, ['jazz', 'vinyl']);
    });
  });

  group('library root', () {
    test('savedLibraryRoot returns null when not set', () async {
      expect(await db.savedLibraryRoot(), isNull);
    });

    test('saveLibraryRoot persists the path', () async {
      await db.saveLibraryRoot('/iCloud/Music');
      expect(await db.savedLibraryRoot(), '/iCloud/Music');
    });

    test('saveLibraryRoot replaces the previous value', () async {
      await db.saveLibraryRoot('/old/path');
      await db.saveLibraryRoot('/new/path');
      expect(await db.savedLibraryRoot(), '/new/path');
    });
  });

  group('release activity', () {
    const path = '/music/album';

    test('allLastActivities returns empty map when nothing recorded', () async {
      expect(await db.allLastActivities(), isEmpty);
    });

    test('setLastActivity persists a timestamp', () async {
      final t = DateTime(2025, 6, 1, 12, 0, 0);
      await db.setLastActivity(path, t);
      final activities = await db.allLastActivities();
      expect(activities[path], t);
    });

    test('setLastActivity overwrites an existing timestamp', () async {
      final older = DateTime(2025, 1, 1);
      final newer = DateTime(2025, 6, 1);
      await db.setLastActivity(path, older);
      await db.setLastActivity(path, newer);
      final activities = await db.allLastActivities();
      expect(activities[path], newer);
    });

    test('allLastActivities returns entries for multiple paths', () async {
      final t1 = DateTime(2025, 1, 1);
      final t2 = DateTime(2025, 6, 1);
      await db.setLastActivity('/album/a', t1);
      await db.setLastActivity('/album/b', t2);
      final activities = await db.allLastActivities();
      expect(activities['/album/a'], t1);
      expect(activities['/album/b'], t2);
    });
  });

  group('selected releases', () {
    const path = '/music/album';

    test('allSelectedPaths returns empty when nothing added', () async {
      expect(await db.allSelectedPaths(), isEmpty);
    });

    test('addSelectedRelease persists a path', () async {
      await db.addSelectedRelease(path);
      expect(await db.allSelectedPaths(), [path]);
    });

    test('addSelectedRelease is idempotent', () async {
      await db.addSelectedRelease(path);
      await db.addSelectedRelease(path);
      expect(await db.allSelectedPaths(), [path]);
    });

    test('removeSelectedRelease removes the path', () async {
      await db.addSelectedRelease(path);
      await db.removeSelectedRelease(path);
      expect(await db.allSelectedPaths(), isEmpty);
    });

    test('removeSelectedRelease on missing path is a no-op', () async {
      await db.removeSelectedRelease(path);
      expect(await db.allSelectedPaths(), isEmpty);
    });

    test('allSelectedPaths returns all added paths', () async {
      await db.addSelectedRelease('/music/a');
      await db.addSelectedRelease('/music/b');
      expect(await db.allSelectedPaths(), containsAll(['/music/a', '/music/b']));
    });
  });

  group('release metadata', () {
    const path = '/music/album';

    test('loadRelease returns null when not saved', () async {
      expect(await db.loadRelease(path), isNull);
    });

    test('saveRelease persists name', () async {
      await db.saveRelease(path, 'My Album');
      final row = await db.loadRelease(path);
      expect(row!['name'], 'My Album');
    });

    test('saveRelease persists optional fields', () async {
      await db.saveRelease(path, 'My Album',
          artPath: '/art.jpg', albumTitle: 'Title', albumArtist: 'Artist');
      final row = await db.loadRelease(path);
      expect(row!['art_path'], '/art.jpg');
      expect(row['album_title'], 'Title');
      expect(row['album_artist'], 'Artist');
    });

    test('saveRelease replaces an existing entry', () async {
      await db.saveRelease(path, 'Old Name');
      await db.saveRelease(path, 'New Name');
      final row = await db.loadRelease(path);
      expect(row!['name'], 'New Name');
    });

    test('deleteRelease removes the release row', () async {
      await db.saveRelease(path, 'My Album');
      await db.deleteRelease(path);
      expect(await db.loadRelease(path), isNull);
    });
  });

  group('resetLibraryData', () {
    test('clears selected_releases, releases, tracks, tags, and release_activity', () async {
      await db.addSelectedRelease('/music/a');
      await db.saveRelease('/music/a', 'Album');
      await db.saveTracks('/music/a', [
        const Track(path: '/music/a/01.mp3', title: 'Track', trackNumber: 1),
      ]);
      await db.addTag('/music/a', 'jazz');
      await db.setLastActivity('/music/a', DateTime(2025, 1, 1));

      await db.resetLibraryData();

      expect(await db.allSelectedPaths(), isEmpty);
      expect(await db.loadRelease('/music/a'), isNull);
      expect(await db.loadTracks('/music/a'), isEmpty);
      expect(await db.tagsForRelease('/music/a'), isEmpty);
      expect(await db.allLastActivities(), isEmpty);
    });

    test('does not clear library_root', () async {
      await db.saveLibraryRoot('/iCloud/Music');
      await db.resetLibraryData();
      expect(await db.savedLibraryRoot(), '/iCloud/Music');
    });
  });

  group('tracks', () {
    const folderPath = '/music/album';

    test('loadTracks returns empty when none saved', () async {
      expect(await db.loadTracks(folderPath), isEmpty);
    });

    test('saveTracks persists tracks ordered by track number', () async {
      await db.saveTracks(folderPath, [
        const Track(path: '/music/album/02.mp3', title: 'B', trackNumber: 2),
        const Track(path: '/music/album/01.mp3', title: 'A', trackNumber: 1),
      ]);
      final rows = await db.loadTracks(folderPath);
      expect(rows.length, 2);
      expect(rows[0]['track_number'], 1);
      expect(rows[0]['title'], 'A');
      expect(rows[1]['track_number'], 2);
      expect(rows[1]['title'], 'B');
    });

    test('saveTracks persists artist field', () async {
      await db.saveTracks(folderPath, [
        const Track(path: '/music/album/01.mp3', title: 'Track', trackNumber: 1, artist: 'Bob'),
      ]);
      final rows = await db.loadTracks(folderPath);
      expect(rows.first['artist'], 'Bob');
    });

    test('saveTracks replaces existing tracks for the folder', () async {
      await db.saveTracks(folderPath, [
        const Track(path: '/music/album/01.mp3', title: 'Old', trackNumber: 1),
      ]);
      await db.saveTracks(folderPath, [
        const Track(path: '/music/album/01.mp3', title: 'New', trackNumber: 1),
      ]);
      final rows = await db.loadTracks(folderPath);
      expect(rows.length, 1);
      expect(rows.first['title'], 'New');
    });

    test('deleteRelease also removes associated tracks', () async {
      await db.saveRelease(folderPath, 'Album');
      await db.saveTracks(folderPath, [
        const Track(path: '/music/album/01.mp3', title: 'Track', trackNumber: 1),
      ]);
      await db.deleteRelease(folderPath);
      expect(await db.loadTracks(folderPath), isEmpty);
    });
  });
}
