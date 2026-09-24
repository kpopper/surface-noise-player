// TEMPORARY MIGRATION AID — see issue #42 and the "Migration export/import"
// section of CAPABILITIES.md.
//
// Carries tags and activity timestamps across the TestFlight bundle-ID
// change, since a new bundle ID makes iOS treat the app as brand new and
// its local database starts empty. Delete this file (and its test), the
// "Export for migration" app bar button in library_screen.dart, and the
// importIfPresent call in LibraryProvider.pickFolder() once the migration
// is done and the app is confirmed working under the new bundle ID.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/release.dart';
import 'database_service.dart';

const migrationExportFileName = '_surface_noise_migration_export.json';

class MigrationExportService {
  static MigrationExportService? _instance;
  static MigrationExportService get instance =>
      _instance ??= MigrationExportService._();
  final DatabaseService _db;

  MigrationExportService._([DatabaseService? db])
      : _db = db ?? DatabaseService.instance;

  @visibleForTesting
  factory MigrationExportService.forTest(DatabaseService db) =>
      MigrationExportService._(db);

  // Writes tags and activity timestamps for every given release to a JSON
  // file at the root of the library folder, keyed by folder name (not full
  // path, so it still matches after the folder is picked again from a
  // fresh install where the OS may resolve it to a different absolute
  // path).
  Future<void> exportTo(String rootPath, List<Release> releases) async {
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'releases': {
        for (final r in releases)
          p.basename(r.folderPath): {
            'tags': r.tags,
            if (r.lastActivityAt != null)
              'lastActivityAt': r.lastActivityAt!.millisecondsSinceEpoch,
          },
      },
    };
    final file = File(p.join(rootPath, migrationExportFileName));
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  // Looks for an export file at the root of the given library folder and,
  // if found, applies its tags and activity timestamps directly to the
  // database, keyed by folder name resolved against rootPath. Safe to call
  // even before any release rows exist for that folder — the following
  // library sync creates them, and they pick up the already-stored
  // tags/activity once loaded. Returns whether an export file was found.
  Future<bool> importIfPresent(String rootPath) async {
    final file = File(p.join(rootPath, migrationExportFileName));
    if (!await file.exists()) return false;

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }

    final releases = data['releases'] as Map<String, dynamic>? ?? {};
    for (final entry in releases.entries) {
      final folderPath = p.join(rootPath, entry.key);
      final info = entry.value as Map<String, dynamic>;
      for (final tag in (info['tags'] as List? ?? const [])) {
        await _db.addTag(folderPath, tag as String);
      }
      final activityMs = info['lastActivityAt'] as int?;
      if (activityMs != null) {
        await _db.setLastActivity(
            folderPath, DateTime.fromMillisecondsSinceEpoch(activityMs));
      }
    }
    return true;
  }
}
