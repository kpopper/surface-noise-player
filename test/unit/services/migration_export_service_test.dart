import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/database_service.dart';
import 'package:surface_noise_player/services/migration_export_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService db;
  late MigrationExportService migration;
  late Directory tempDir;

  setUp(() async {
    db = DatabaseService.forTest(inMemoryDatabasePath);
    migration = MigrationExportService.forTest(db);
    tempDir = await Directory.systemTemp.createTemp('migration_export_test');
  });

  tearDown(() async {
    await db.closeForTest();
    await tempDir.delete(recursive: true);
  });

  Release makeRelease(String folderName,
          {List<String> tags = const [], DateTime? lastActivityAt}) =>
      Release(
        folderPath: p.join(tempDir.path, folderName),
        name: folderName,
        tracks: const [],
        tags: tags,
        lastActivityAt: lastActivityAt,
      );

  group('exportTo', () {
    test('writes tags and activity keyed by folder name', () async {
      final activity = DateTime(2026, 1, 1);
      await migration.exportTo(tempDir.path, [
        makeRelease('Artist - Album',
            tags: ['jazz', 'favourite'], lastActivityAt: activity),
        makeRelease('No Tags Album'),
      ]);

      final file =
          File(p.join(tempDir.path, migrationExportFileName));
      expect(await file.exists(), isTrue);
      final data = jsonDecode(await file.readAsString()) as Map;
      final releases = data['releases'] as Map;
      expect(releases['Artist - Album']['tags'], ['jazz', 'favourite']);
      expect(releases['Artist - Album']['lastActivityAt'],
          activity.millisecondsSinceEpoch);
      expect(releases['No Tags Album']['tags'], isEmpty);
      expect(releases['No Tags Album'].containsKey('lastActivityAt'), isFalse);
    });
  });

  group('importIfPresent', () {
    test('returns false when no export file exists', () async {
      expect(await migration.importIfPresent(tempDir.path), isFalse);
    });

    test('returns false and does not throw for malformed JSON', () async {
      await File(p.join(tempDir.path, migrationExportFileName))
          .writeAsString('not json');
      expect(await migration.importIfPresent(tempDir.path), isFalse);
    });

    test('applies tags and activity to the database, keyed by folder name',
        () async {
      final activity = DateTime(2026, 1, 1);
      await migration.exportTo(tempDir.path, [
        makeRelease('Artist - Album',
            tags: ['jazz', 'favourite'], lastActivityAt: activity),
      ]);
      // Simulate a fresh install's empty database.
      db = DatabaseService.forTest(inMemoryDatabasePath);
      migration = MigrationExportService.forTest(db);

      final found = await migration.importIfPresent(tempDir.path);

      expect(found, isTrue);
      final folderPath = p.join(tempDir.path, 'Artist - Album');
      expect(await db.tagsForRelease(folderPath),
          unorderedEquals(['favourite', 'jazz']));
      expect((await db.allLastActivities())[folderPath], activity);
    });

    test('round-trips a release with no tags and no activity', () async {
      await migration.exportTo(tempDir.path, [makeRelease('No Tags Album')]);

      final found = await migration.importIfPresent(tempDir.path);

      expect(found, isTrue);
      final folderPath = p.join(tempDir.path, 'No Tags Album');
      expect(await db.tagsForRelease(folderPath), isEmpty);
      expect((await db.allLastActivities()).containsKey(folderPath), isFalse);
    });
  });
}
