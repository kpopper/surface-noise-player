import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/folder_info.dart';
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
  final BookmarkService _bookmarks;

  LibraryService._([DatabaseService? db, MetadataService? metadata, BookmarkService? bookmarks])
      : _db = db ?? DatabaseService.instance,
        _metadata = metadata ?? MetadataService.instance,
        _bookmarks = bookmarks ?? BookmarkService.instance;

  static LibraryService get instance => _instance ??= LibraryService._();

  @visibleForTesting
  factory LibraryService.forTest(DatabaseService db,
          {MetadataService? metadata, BookmarkService? bookmarks}) =>
      LibraryService._(db, metadata, bookmarks);

  Future<String?> pickLibraryFolder() async {
    final currentRoot = await _db.savedLibraryRoot();
    final path = await _bookmarks.pickFolder();
    if (path != null) {
      if (currentRoot != null && path != currentRoot) {
        await _db.resetLibraryData();
      }
      await _db.saveLibraryRoot(path);
    }
    return path;
  }

  Future<String?> getSavedRoot() => _db.savedLibraryRoot();

  Future<List<Release>> loadSelectedReleases() async {
    final paths = await _db.allSelectedPaths();
    final activities = await _db.allLastActivities();
    final releases = <Release>[];
    for (final path in paths) {
      final releaseData = await _db.loadRelease(path);
      if (releaseData == null) continue;
      final trackRows = await _db.loadTracks(path);
      final tags = await _db.tagsForRelease(path);
      final tracks = trackRows.map((row) => Track(
        path: row['file_path'] as String,
        title: row['title'] as String,
        trackNumber: row['track_number'] as int,
        artist: row['artist'] as String?,
      )).toList();
      // Validate the stored art path — paths from previous installs or
      // old temp-directory extractions will no longer exist on disk.
      final rawArtPath = releaseData['art_path'] as String?;
      final artPath = rawArtPath != null && File(rawArtPath).existsSync()
          ? rawArtPath
          : null;

      releases.add(Release(
        folderPath: path,
        name: releaseData['name'] as String,
        tracks: tracks,
        tags: tags,
        artPath: artPath,
        albumTitle: releaseData['album_title'] as String?,
        albumArtist: releaseData['album_artist'] as String?,
        lastActivityAt: activities[path],
      ));
    }
    return releases;
  }

  Future<Release?> selectRelease(String folderPath) async {
    final scan = await _scanFolder(folderPath);
    if (scan.tracks.isEmpty) return null;

    final lastActivityAt = DateTime.now();
    await _db.setLastActivity(folderPath, lastActivityAt);

    final tags = await _db.tagsForRelease(folderPath);
    final firstTrackPath = scan.tracks.first.path;
    final artPath = await _findArtFile(folderPath, firstTrackPath: firstTrackPath);
    final folderName = folderPath.split('/').last;
    final name = (scan.albumArtist != null && scan.albumTitle != null)
        ? '${scan.albumArtist} - ${scan.albumTitle}'
        : folderName;

    await _db.saveRelease(folderPath, name,
        artPath: artPath, albumTitle: scan.albumTitle, albumArtist: scan.albumArtist);
    await _db.saveTracks(folderPath, scan.tracks);
    await _db.addSelectedRelease(folderPath);

    return Release(
      folderPath: folderPath,
      name: name,
      tracks: scan.tracks,
      tags: tags,
      artPath: artPath,
      albumTitle: scan.albumTitle,
      albumArtist: scan.albumArtist,
      lastActivityAt: lastActivityAt,
    );
  }

  Future<void> deselectRelease(String folderPath) async {
    await _db.removeSelectedRelease(folderPath);
    await _db.deleteRelease(folderPath);
    // tags and release_activity rows are intentionally preserved
  }

  // Re-extract artwork for a release whose stored art path is missing or stale.
  // Returns the new path if artwork was found and saved, null otherwise.
  Future<String?> refreshArtwork(String folderPath) async {
    final trackRows = await _db.loadTracks(folderPath);
    if (trackRows.isEmpty) return null;
    final firstTrackPath = trackRows.first['file_path'] as String;
    final artPath = await _findArtFile(folderPath, firstTrackPath: firstTrackPath);
    if (artPath != null) {
      await _db.updateArtPath(folderPath, artPath);
    }
    return artPath;
  }

  Future<List<FolderInfo>> listAllFolders(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return [];

    final selectedPaths = (await _db.allSelectedPaths()).toSet();
    final folders = <FolderInfo>[];

    await for (final entity in root.list()) {
      if (entity is Directory) {
        final name = entity.path.split('/').last;
        if (name.startsWith('_')) continue;
        folders.add(FolderInfo(
          path: entity.path,
          name: name,
          isSelected: selectedPaths.contains(entity.path),
        ));
      }
    }

    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return folders;
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
