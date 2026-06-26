import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/release.dart';

class DatabaseService {
  static DatabaseService? _instance;
  Database? _db;
  final String? _overridePath;

  DatabaseService._([this._overridePath]);
  static DatabaseService get instance => _instance ??= DatabaseService._();

  @visibleForTesting
  factory DatabaseService.forTest(String dbPath) => DatabaseService._(dbPath);

  @visibleForTesting
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final resolvedPath = _overridePath ?? join(await getDatabasesPath(), 'surface_noise.db');
    return openDatabase(
      resolvedPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tags (
            folder_path TEXT NOT NULL,
            tag TEXT NOT NULL,
            PRIMARY KEY (folder_path, tag)
          )
        ''');
        await db.execute('''
          CREATE TABLE library_root (
            id INTEGER PRIMARY KEY,
            path TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE release_activity (
            folder_path TEXT PRIMARY KEY,
            last_activity_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE selected_releases (
            folder_path TEXT PRIMARY KEY
          )
        ''');
        await db.execute('''
          CREATE TABLE releases (
            folder_path TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            art_path TEXT,
            album_title TEXT,
            album_artist TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE tracks (
            file_path TEXT PRIMARY KEY,
            folder_path TEXT NOT NULL,
            title TEXT NOT NULL,
            track_number INTEGER NOT NULL,
            artist TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE release_activity (
              folder_path TEXT PRIMARY KEY,
              last_activity_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE selected_releases (
              folder_path TEXT PRIMARY KEY
            )
          ''');
          await db.execute('''
            CREATE TABLE releases (
              folder_path TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              art_path TEXT,
              album_title TEXT,
              album_artist TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE tracks (
              file_path TEXT PRIMARY KEY,
              folder_path TEXT NOT NULL,
              title TEXT NOT NULL,
              track_number INTEGER NOT NULL,
              artist TEXT
            )
          ''');
        }
      },
    );
  }

  // MARK: - Library reset

  Future<void> resetLibraryData() async {
    final d = await db;
    await d.delete('selected_releases');
    await d.delete('releases');
    await d.delete('tracks');
    await d.delete('tags');
    await d.delete('release_activity');
  }

  // MARK: - Tags

  Future<List<String>> tagsForRelease(String folderPath) async {
    final d = await db;
    final rows = await d.query(
      'tags',
      columns: ['tag'],
      where: 'folder_path = ?',
      whereArgs: [folderPath],
    );
    return rows.map((r) => r['tag'] as String).toList();
  }

  Future<void> addTag(String folderPath, String tag) async {
    final d = await db;
    await d.insert(
      'tags',
      {'folder_path': folderPath, 'tag': tag},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTag(String folderPath, String tag) async {
    final d = await db;
    await d.delete(
      'tags',
      where: 'folder_path = ? AND tag = ?',
      whereArgs: [folderPath, tag],
    );
  }

  Future<List<String>> allTags() async {
    final d = await db;
    final rows = await d.rawQuery('SELECT DISTINCT tag FROM tags ORDER BY tag');
    return rows.map((r) => r['tag'] as String).toList();
  }

  // MARK: - Library root

  Future<String?> savedLibraryRoot() async {
    final d = await db;
    final rows = await d.query('library_root', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['path'] as String;
  }

  Future<void> saveLibraryRoot(String path) async {
    final d = await db;
    await d.delete('library_root');
    await d.insert('library_root', {'path': path});
  }

  // MARK: - Release activity

  Future<void> setLastActivity(String folderPath, DateTime time) async {
    final d = await db;
    await d.insert(
      'release_activity',
      {'folder_path': folderPath, 'last_activity_at': time.millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, DateTime>> allLastActivities() async {
    final d = await db;
    final rows = await d.query('release_activity');
    return {
      for (final r in rows)
        r['folder_path'] as String:
            DateTime.fromMillisecondsSinceEpoch(r['last_activity_at'] as int),
    };
  }

  // MARK: - Selected releases

  Future<void> addSelectedRelease(String folderPath) async {
    final d = await db;
    await d.insert(
      'selected_releases',
      {'folder_path': folderPath},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeSelectedRelease(String folderPath) async {
    final d = await db;
    await d.delete(
      'selected_releases',
      where: 'folder_path = ?',
      whereArgs: [folderPath],
    );
  }

  Future<List<String>> allSelectedPaths() async {
    final d = await db;
    final rows = await d.query('selected_releases');
    return rows.map((r) => r['folder_path'] as String).toList();
  }

  // MARK: - Release metadata

  Future<void> saveRelease(String folderPath, String name,
      {String? artPath, String? albumTitle, String? albumArtist}) async {
    final d = await db;
    await d.insert(
      'releases',
      {
        'folder_path': folderPath,
        'name': name,
        'art_path': artPath,
        'album_title': albumTitle,
        'album_artist': albumArtist,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadRelease(String folderPath) async {
    final d = await db;
    final rows = await d.query(
      'releases',
      where: 'folder_path = ?',
      whereArgs: [folderPath],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateArtPath(String folderPath, String artPath) async {
    final d = await db;
    await d.update(
      'releases',
      {'art_path': artPath},
      where: 'folder_path = ?',
      whereArgs: [folderPath],
    );
  }

  Future<void> deleteRelease(String folderPath) async {
    final d = await db;
    await d.delete('releases', where: 'folder_path = ?', whereArgs: [folderPath]);
    await d.delete('tracks', where: 'folder_path = ?', whereArgs: [folderPath]);
  }

  // MARK: - Tracks

  Future<void> saveTracks(String folderPath, List<Track> tracks) async {
    final d = await db;
    await d.delete('tracks', where: 'folder_path = ?', whereArgs: [folderPath]);
    for (final t in tracks) {
      await d.insert('tracks', {
        'file_path': t.path,
        'folder_path': folderPath,
        'title': t.title,
        'track_number': t.trackNumber,
        'artist': t.artist,
      });
    }
  }

  Future<List<Map<String, dynamic>>> loadTracks(String folderPath) async {
    final d = await db;
    return d.query(
      'tracks',
      where: 'folder_path = ?',
      whereArgs: [folderPath],
      orderBy: 'track_number ASC',
    );
  }
}
