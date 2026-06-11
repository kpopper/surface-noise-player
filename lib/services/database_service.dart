import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
      version: 1,
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
      },
    );
  }

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
}
