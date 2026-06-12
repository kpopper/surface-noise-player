import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
}
