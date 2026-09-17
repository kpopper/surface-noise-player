import 'dart:io';
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

    test('a fresh release defaults to first_track_scanned = 0', () async {
      await db.saveRelease(path, 'My Album');
      final row = await db.loadRelease(path);
      expect(row!['first_track_scanned'], 0);
    });

    test('deleteRelease removes the release row', () async {
      await db.saveRelease(path, 'My Album');
      await db.deleteRelease(path);
      expect(await db.loadRelease(path), isNull);
    });
  });

  group('allReleasePaths', () {
    test('returns empty when no releases saved', () async {
      expect(await db.allReleasePaths(), isEmpty);
    });

    test('returns all saved release folder_paths', () async {
      await db.saveRelease('/music/a', 'Album A');
      await db.saveRelease('/music/b', 'Album B');
      expect(await db.allReleasePaths(), containsAll(['/music/a', '/music/b']));
    });
  });

  group('loadAllReleases', () {
    test('returns empty when no releases saved', () async {
      expect(await db.loadAllReleases(), isEmpty);
    });

    test('returns full rows for every saved release', () async {
      await db.saveRelease('/music/a', 'Album A',
          artPath: '/art.jpg', albumTitle: 'Title', albumArtist: 'Artist');
      final rows = await db.loadAllReleases();
      expect(rows.length, 1);
      expect(rows.first['folder_path'], '/music/a');
      expect(rows.first['name'], 'Album A');
      expect(rows.first['art_path'], '/art.jpg');
      expect(rows.first['album_title'], 'Title');
      expect(rows.first['album_artist'], 'Artist');
    });
  });

  group('unscannedReleasePaths', () {
    test('returns a release that has never been scanned', () async {
      await db.saveRelease('/music/a', 'Album A');
      expect(await db.unscannedReleasePaths(), ['/music/a']);
    });

    test('excludes a release once markFirstTrackScanned is called', () async {
      await db.saveRelease('/music/a', 'Album A');
      await db.markFirstTrackScanned('/music/a');
      expect(await db.unscannedReleasePaths(), isEmpty);
    });
  });

  group('markFirstTrackScanned', () {
    test('sets first_track_scanned to 1', () async {
      await db.saveRelease('/music/a', 'Album A');
      await db.markFirstTrackScanned('/music/a');
      final row = await db.loadRelease('/music/a');
      expect(row!['first_track_scanned'], 1);
    });

    test('does not affect other releases', () async {
      await db.saveRelease('/music/a', 'Album A');
      await db.saveRelease('/music/b', 'Album B');
      await db.markFirstTrackScanned('/music/a');
      final rowB = await db.loadRelease('/music/b');
      expect(rowB!['first_track_scanned'], 0);
    });
  });

  group('resetLibraryData', () {
    test('clears releases, tracks, tags, and release_activity', () async {
      await db.saveRelease('/music/a', 'Album');
      await db.saveTracks('/music/a', [
        const Track(path: '/music/a/01.mp3', title: 'Track', trackNumber: 1),
      ]);
      await db.addTag('/music/a', 'jazz');
      await db.setLastActivity('/music/a', DateTime(2025, 1, 1));

      await db.resetLibraryData();

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
        const Track(
            path: '/music/album/01.mp3',
            title: 'Track',
            trackNumber: 1,
            artist: 'Bob'),
      ]);
      final rows = await db.loadTracks(folderPath);
      expect(rows.first['artist'], 'Bob');
    });

    test('a fresh track defaults to metadata_read = 0', () async {
      await db.saveTracks(folderPath, [
        const Track(
            path: '/music/album/01.mp3', title: 'Track', trackNumber: 1),
      ]);
      final rows = await db.loadTracks(folderPath);
      expect(rows.first['metadata_read'], 0);
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
        const Track(
            path: '/music/album/01.mp3', title: 'Track', trackNumber: 1),
      ]);
      await db.deleteRelease(folderPath);
      expect(await db.loadTracks(folderPath), isEmpty);
    });
  });

  group('updateTrackFileMetadata', () {
    const folderPath = '/music/album';
    const filePath = '/music/album/01.mp3';

    test('updates title, trackNumber, and artist', () async {
      await db.saveTracks(folderPath, [
        const Track(path: filePath, title: 'Old', trackNumber: 1),
      ]);
      await db.updateTrackFileMetadata(filePath,
          title: 'New', trackNumber: 3, artist: 'Bob');
      final row = (await db.loadTracks(folderPath)).first;
      expect(row['title'], 'New');
      expect(row['track_number'], 3);
      expect(row['artist'], 'Bob');
    });

    test('does not set metadata_read', () async {
      await db.saveTracks(folderPath, [
        const Track(path: filePath, title: 'Old', trackNumber: 1),
      ]);
      await db.updateTrackFileMetadata(filePath, title: 'New', trackNumber: 1);
      final row = (await db.loadTracks(folderPath)).first;
      expect(row['metadata_read'], 0);
    });

    test('does not affect other tracks in the same folder', () async {
      await db.saveTracks(folderPath, [
        const Track(path: filePath, title: 'One', trackNumber: 1),
        const Track(path: '/music/album/02.mp3', title: 'Two', trackNumber: 2),
      ]);
      await db.updateTrackFileMetadata(filePath,
          title: 'Updated', trackNumber: 1);
      final rows = await db.loadTracks(folderPath);
      expect(
          rows.firstWhere(
              (r) => r['file_path'] == '/music/album/02.mp3')['title'],
          'Two');
    });
  });

  group('markTrackMetadataRead', () {
    const folderPath = '/music/album';
    const filePath = '/music/album/01.mp3';

    test('updates title, trackNumber, and artist', () async {
      await db.saveTracks(folderPath, [
        const Track(path: filePath, title: 'Old', trackNumber: 1),
      ]);
      await db.markTrackMetadataRead(filePath,
          title: 'New', trackNumber: 2, artist: 'Bob');
      final row = (await db.loadTracks(folderPath)).first;
      expect(row['title'], 'New');
      expect(row['track_number'], 2);
      expect(row['artist'], 'Bob');
    });

    test('sets metadata_read to 1', () async {
      await db.saveTracks(folderPath, [
        const Track(path: filePath, title: 'Old', trackNumber: 1),
      ]);
      await db.markTrackMetadataRead(filePath, title: 'New', trackNumber: 1);
      final row = (await db.loadTracks(folderPath)).first;
      expect(row['metadata_read'], 1);
    });
  });

  group('schema v3 -> v4 migration', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('snp_migration_test_');
      dbPath = '${tempDir.path}/test.db';
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
        'drops selected_releases, adds new columns, and marks existing releases as scanned',
        () async {
      // Seed a v3 database directly, matching the pre-migration schema.
      final v3 =
          await openDatabase(dbPath, version: 3, onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE selected_releases (folder_path TEXT PRIMARY KEY)
        ''');
        await db.execute('''
          CREATE TABLE releases (
            folder_path TEXT PRIMARY KEY, name TEXT NOT NULL,
            art_path TEXT, album_title TEXT, album_artist TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE tracks (
            file_path TEXT PRIMARY KEY, folder_path TEXT NOT NULL,
            title TEXT NOT NULL, track_number INTEGER NOT NULL, artist TEXT
          )
        ''');
      });
      await v3.insert('selected_releases', {'folder_path': '/music/a'});
      await v3
          .insert('releases', {'folder_path': '/music/a', 'name': 'Album A'});
      await v3.insert('tracks', {
        'file_path': '/music/a/01.mp3',
        'folder_path': '/music/a',
        'title': 'Track',
        'track_number': 1,
      });
      await v3.close();

      final migrated = DatabaseService.forTest(dbPath);
      final d = await migrated.db;

      expect(
        () => d.query('selected_releases'),
        throwsA(isA<DatabaseException>()),
      );
      final releaseRow = await migrated.loadRelease('/music/a');
      expect(releaseRow!['first_track_scanned'],
          1); // pre-existing release, not re-scanned
      final trackRow = (await migrated.loadTracks('/music/a')).first;
      expect(trackRow['metadata_read'], 0);

      await migrated.closeForTest();
    });
  });
}
