import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/release.dart';
import 'bookmark_service.dart';
import 'database_service.dart';
import 'metadata_service.dart';

const _audioExtensions = {'.mp3', '.flac', '.aac', '.m4a', '.wav', '.ogg', '.opus', '.aiff', '.aif'};
const _preferredArtFilenames = ['cover.jpg', 'folder.jpg', 'artwork.jpg', 'front.jpg'];
const _artExtensions = {'.jpg', '.jpeg', '.png'};

typedef _FolderScan = ({List<Track> tracks, String? albumArtist, String? albumTitle});

class LibraryService {
  static LibraryService? _instance;
  final DatabaseService _db;
  final MetadataService _metadata;

  LibraryService._([DatabaseService? db, MetadataService? metadata])
      : _db = db ?? DatabaseService.instance,
        _metadata = metadata ?? MetadataService.instance;

  static LibraryService get instance => _instance ??= LibraryService._();

  @visibleForTesting
  factory LibraryService.forTest(DatabaseService db, {MetadataService? metadata}) =>
      LibraryService._(db, metadata);

  Future<String?> pickLibraryFolder() async {
    final path = await BookmarkService.instance.pickFolder();
    if (path != null) {
      await _db.saveLibraryRoot(path);
    }
    return path;
  }

  Future<String?> getSavedRoot() => _db.savedLibraryRoot();

  Future<List<Release>> scanLibrary(String rootPath) async {
    await _metadata.cleanupArtworkCache();

    final root = Directory(rootPath);
    if (!await root.exists()) return [];

    final activities = await _db.allLastActivities();
    final releases = <Release>[];

    await for (final entity in root.list()) {
      if (entity is Directory) {
        final scan = await _scanFolder(entity.path);
        if (scan.tracks.isNotEmpty) {
          final tags = await _db.tagsForRelease(entity.path);
          final firstTrackPath = scan.tracks.first.path;
          final artPath = await _findArtFile(entity.path, firstTrackPath: firstTrackPath);
          final folderName = entity.path.split('/').last;
          final name = (scan.albumArtist != null && scan.albumTitle != null)
              ? '${scan.albumArtist} - ${scan.albumTitle}'
              : folderName;
          releases.add(Release(
            folderPath: entity.path,
            name: name,
            tracks: scan.tracks,
            tags: tags,
            artPath: artPath,
            albumTitle: scan.albumTitle,
            albumArtist: scan.albumArtist,
            lastActivityAt: activities[entity.path],
          ));
        }
      }
    }

    return releases;
  }

  Future<List<Release>> quickScanLibrary(String rootPath, List<Release> existing) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return [];

    final existingByPath = {for (final r in existing) r.folderPath: r};
    final knownActivities = await _db.allLastActivities();
    final currentPaths = <String>{};
    final newReleases = <Release>[];

    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      currentPaths.add(entity.path);
      if (existingByPath.containsKey(entity.path)) continue;

      final scan = await _scanFolder(entity.path);
      if (scan.tracks.isEmpty) continue;

      // Only assign a new timestamp if the folder has never been seen before.
      // Folders known from a previous session (in DB but not in memory) keep
      // their existing timestamp so play history is not overwritten on restart.
      final existingActivity = knownActivities[entity.path];
      final DateTime? lastActivityAt;
      if (existingActivity == null) {
        final now = DateTime.now();
        await _db.setLastActivity(entity.path, now);
        lastActivityAt = now;
      } else {
        lastActivityAt = existingActivity;
      }

      final tags = await _db.tagsForRelease(entity.path);
      final firstTrackPath = scan.tracks.first.path;
      final artPath = await _findArtFile(entity.path, firstTrackPath: firstTrackPath);
      final folderName = entity.path.split('/').last;
      final name = (scan.albumArtist != null && scan.albumTitle != null)
          ? '${scan.albumArtist} - ${scan.albumTitle}'
          : folderName;
      newReleases.add(Release(
        folderPath: entity.path,
        name: name,
        tracks: scan.tracks,
        tags: tags,
        artPath: artPath,
        albumTitle: scan.albumTitle,
        albumArtist: scan.albumArtist,
        lastActivityAt: lastActivityAt,
      ));
    }

    return [
      ...existing.where((r) => currentPaths.contains(r.folderPath)),
      ...newReleases,
    ];
  }

  Future<void> recordPlay(String folderPath) => _db.setLastActivity(folderPath, DateTime.now());

  Future<_FolderScan> _scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    final audioFiles = <File>[];

    await for (final entity in dir.list()) {
      if (entity is File && _audioExtensions.any(entity.path.toLowerCase().endsWith)) {
        audioFiles.add(entity);
      }
    }

    audioFiles.sort((a, b) => a.path.compareTo(b.path));

    String? albumArtist;
    String? albumTitle;
    final tracks = <Track>[];

    for (var i = 0; i < audioFiles.length; i++) {
      final file = audioFiles[i];
      final filename = file.path.split('/').last;
      final meta = await _metadata.readMetadata(file.path);

      if (i == 0) {
        albumArtist = meta.albumArtist?.isNotEmpty == true ? meta.albumArtist : null;
        albumTitle = meta.albumTitle?.isNotEmpty == true ? meta.albumTitle : null;
      }

      tracks.add(Track(
        path: file.path,
        title: meta.title?.isNotEmpty == true ? meta.title! : _cleanTitle(filename),
        trackNumber: meta.trackNumber ?? (i + 1),
        artist: meta.artist?.isNotEmpty == true ? meta.artist : null,
      ));
    }

    tracks.sort((a, b) => a.trackNumber.compareTo(b.trackNumber));
    return (tracks: tracks, albumArtist: albumArtist, albumTitle: albumTitle);
  }

  Future<String?> _findArtFile(String folderPath, {String? firstTrackPath}) async {
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
    if (firstTrackPath != null) {
      return await _metadata.extractArtwork(firstTrackPath);
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
