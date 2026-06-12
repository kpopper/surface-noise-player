import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/release.dart';
import 'bookmark_service.dart';
import 'database_service.dart';

const _audioExtensions = {'.mp3', '.flac', '.aac', '.m4a', '.wav', '.ogg', '.opus', '.aiff'};
const _preferredArtFilenames = ['cover.jpg', 'folder.jpg', 'artwork.jpg', 'front.jpg'];
const _artExtensions = {'.jpg', '.jpeg', '.png'};

class LibraryService {
  static LibraryService? _instance;
  final DatabaseService _db;

  LibraryService._([DatabaseService? db]) : _db = db ?? DatabaseService.instance;
  static LibraryService get instance => _instance ??= LibraryService._();

  @visibleForTesting
  factory LibraryService.forTest(DatabaseService db) => LibraryService._(db);

  Future<String?> pickLibraryFolder() async {
    final path = await BookmarkService.instance.pickFolder();
    if (path != null) {
      await _db.saveLibraryRoot(path);
    }
    return path;
  }

  Future<String?> getSavedRoot() => _db.savedLibraryRoot();

  Future<List<Release>> scanLibrary(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return [];

    final releases = <Release>[];

    await for (final entity in root.list()) {
      if (entity is Directory) {
        final tracks = await _tracksInFolder(entity.path);
        if (tracks.isNotEmpty) {
          final tags = await _db.tagsForRelease(entity.path);
          final artPath = await _findArtFile(entity.path);
          releases.add(Release(
            folderPath: entity.path,
            name: entity.path.split('/').last,
            tracks: tracks,
            tags: tags,
            artPath: artPath,
          ));
        }
      }
    }

    releases.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return releases;
  }

  Future<List<Track>> _tracksInFolder(String folderPath) async {
    final dir = Directory(folderPath);
    final files = <FileSystemEntity>[];

    await for (final entity in dir.list()) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        if (_audioExtensions.any(ext.endsWith)) {
          files.add(entity);
        }
      }
    }

    files.sort((a, b) => a.path.compareTo(b.path));

    return files.indexed.map((entry) {
      final (i, file) = entry;
      final filename = file.path.split('/').last;
      final title = LibraryService._cleanTitle(filename);
      return Track(path: file.path, title: title, trackNumber: i + 1);
    }).toList();
  }

  Future<String?> _findArtFile(String folderPath) async {
    for (final name in _preferredArtFilenames) {
      final f = File('$folderPath/$name');
      if (await f.exists()) return f.path;
    }
    final dir = Directory(folderPath);
    await for (final entity in dir.list()) {
      if (entity is File && _artExtensions.any(entity.path.toLowerCase().endsWith)) {
        return entity.path;
      }
    }
    return null;
  }

  @visibleForTesting
  static String cleanTitle(String filename) => _cleanTitle(filename);

  static String _cleanTitle(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    var name = dotIndex >= 0 ? filename.substring(0, dotIndex) : filename;
    // Strip leading track number patterns like "01 - " or "01. "
    name = name.replaceFirst(RegExp(r'^\d+[\s.\-–]+'), '');
    return name.trim();
  }

  Future<void> addTag(String folderPath, String tag) => _db.addTag(folderPath, tag.trim().toLowerCase());
  Future<void> removeTag(String folderPath, String tag) => _db.removeTag(folderPath, tag);
  Future<List<String>> allTags() => _db.allTags();
}
