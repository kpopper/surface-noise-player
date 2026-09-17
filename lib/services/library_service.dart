import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/release.dart';
import 'bookmark_service.dart';
import 'database_service.dart';
import 'metadata_service.dart';

const _audioExtensions = {
  '.mp3',
  '.flac',
  '.aac',
  '.m4a',
  '.wav',
  '.ogg',
  '.opus',
  '.aiff',
  '.aif'
};
const _preferredArtFilenames = [
  'cover.jpg',
  'folder.jpg',
  'artwork.jpg',
  'front.jpg'
];
const _artExtensions = {'.jpg', '.jpeg', '.png'};

class LibraryService {
  static LibraryService? _instance;
  final DatabaseService _db;
  final MetadataService _metadata;
  final BookmarkService _bookmarks;

  // How often to re-check availability while waiting for a release's first
  // track to download during a scan, and how long to wait before giving up
  // (much shorter than playback's wait — this runs unattended, possibly
  // across many releases in one sync, so a slow/offline network shouldn't
  // stall the whole sync for a long time per release).
  final Duration _scanPollInterval;
  final Duration _scanDownloadTimeout;

  LibraryService._([
    DatabaseService? db,
    MetadataService? metadata,
    BookmarkService? bookmarks,
    Duration? scanPollInterval,
    Duration? scanDownloadTimeout,
  ])  : _db = db ?? DatabaseService.instance,
        _metadata = metadata ?? MetadataService.instance,
        _bookmarks = bookmarks ?? BookmarkService.instance,
        _scanPollInterval = scanPollInterval ?? const Duration(seconds: 1),
        _scanDownloadTimeout =
            scanDownloadTimeout ?? const Duration(seconds: 30);

  static LibraryService get instance => _instance ??= LibraryService._();

  @visibleForTesting
  factory LibraryService.forTest(
    DatabaseService db, {
    MetadataService? metadata,
    BookmarkService? bookmarks,
    Duration? scanPollInterval,
    Duration? scanDownloadTimeout,
  }) =>
      LibraryService._(
          db, metadata, bookmarks, scanPollInterval, scanDownloadTimeout);

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

  Future<List<Release>> loadLibrary() async {
    final releaseRows = await _db.loadAllReleases();
    final activities = await _db.allLastActivities();
    final releases = <Release>[];
    for (final releaseData in releaseRows) {
      final path = releaseData['folder_path'] as String;
      final trackRows = await _db.loadTracks(path);
      final tags = await _db.tagsForRelease(path);
      final tracks = trackRows
          .map((row) => Track(
                path: row['file_path'] as String,
                title: row['title'] as String,
                trackNumber: row['track_number'] as int,
                artist: row['artist'] as String?,
                metadataRead: (row['metadata_read'] as int) == 1,
              ))
          .toList();
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

  // Syncs the database with what's actually on disk: adds a release for
  // every subfolder not yet known, removes a release for every known
  // subfolder that's gone (preserving its tags/activity), and retries any
  // release whose first-track scan previously timed out. Releases already
  // known and still present are left completely untouched.
  //
  // onProgress, if given, is called after each individual release is added,
  // removed, or retried — lets a caller (e.g. the UI) reload and display
  // changes as they happen, rather than waiting for the whole sync to
  // finish, which can take a while across a large library.
  Future<void> syncLibrary(String rootPath,
      {void Function()? onProgress}) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return;

    final onDisk = <String>{};
    await for (final entity in root.list()) {
      if (entity is Directory) {
        final name = entity.path.split('/').last;
        if (!name.startsWith('_')) onDisk.add(entity.path);
      }
    }

    final existing = (await _db.allReleasePaths()).toSet();

    final removed = existing.difference(onDisk);
    for (final path in removed) {
      await _db.deleteRelease(path);
      onProgress?.call();
    }

    final added = onDisk.difference(existing);
    final unresolved =
        await _db.unscannedReleasePaths(); // excludes just-removed rows

    final tasks = <Future<void> Function()>[
      for (final path in added)
        () async {
          await _discoverRelease(path);
          onProgress?.call();
        },
      for (final path in unresolved)
        () async {
          await _retryUnresolvedRelease(path);
          onProgress?.call();
        },
    ];
    await _runWithConcurrency(tasks);
  }

  Future<void> _runWithConcurrency(List<Future<void> Function()> tasks,
      {int limit = 8}) async {
    for (var i = 0; i < tasks.length; i += limit) {
      await Future.wait(tasks.skip(i).take(limit).map((t) => t()));
    }
  }

  Future<void> _discoverRelease(String folderPath) async {
    final tracks = await _listTracksQuick(folderPath);
    if (tracks.isEmpty) return; // empty folder never gets a release row
    final folderName = folderPath.split('/').last;
    await _db.saveRelease(
        folderPath, folderName); // seed with folder-name fallback immediately
    await _db.saveTracks(folderPath, tracks);
    await _db.setLastActivity(
        folderPath, DateTime.now()); // discovery-time activity
    await _resolveFirstTrack(folderPath, folderName);
  }

  Future<void> _retryUnresolvedRelease(String folderPath) =>
      _resolveFirstTrack(folderPath, folderPath.split('/').last);

  // Attempts to resolve album-level info (name, art, albumArtist/albumTitle)
  // from the release's first track (by sorted filename), downloading and
  // evicting it as needed. Shared by brand-new discovery and by retrying a
  // release whose first scan previously timed out. Does not touch the rest
  // of the release's track rows. Deliberately does not attempt a MusicBrainz
  // lookup — that's a later, lazy "only when the release view is opened"
  // feature.
  Future<void> _resolveFirstTrack(String folderPath, String folderName) async {
    final quickTracks = await _listTracksQuick(folderPath);
    if (quickTracks.isEmpty) {
      return; // folder now empty; next sync's disk-diff will remove it
    }
    final firstTrackPath = quickTracks.first.path;

    var artPath =
        await _findArtFile(folderPath); // folder-image check only — no download
    await _bookmarks.downloadFile(firstTrackPath);
    if (!await _awaitFileAvailable(firstTrackPath)) {
      // Still worth keeping any folder-image art found without a download,
      // even though the metadata read didn't happen this time. The release
      // stays unscanned either way, so it's retried on the next sync.
      if (artPath != null) await _db.updateArtPath(folderPath, artPath);
      return;
    }

    final meta = await _metadata.readMetadata(firstTrackPath);
    final albumArtist =
        meta.albumArtist?.isNotEmpty == true ? meta.albumArtist : null;
    final albumTitle =
        meta.albumTitle?.isNotEmpty == true ? meta.albumTitle : null;
    artPath ??= await _metadata.extractArtwork(firstTrackPath);
    await _bookmarks.evictFile(firstTrackPath); // best-effort

    final name = (albumArtist != null && albumTitle != null)
        ? '$albumArtist - $albumTitle'
        : folderName;
    await _db.saveRelease(folderPath, name,
        artPath: artPath, albumTitle: albumTitle, albumArtist: albumArtist);
    // Deliberately not persisted to the track row: only album-level info
    // (name/art/albumArtist/albumTitle above) comes from this scan. The
    // first track's own title/artist stay filename-derived, same as every
    // other track, until it's actually played (see Audio metadata) —
    // otherwise it would show real metadata while its siblings still show
    // filenames.
    await _db.markFirstTrackScanned(folderPath);
  }

  // Lists a folder's audio files purely from their filenames — no metadata
  // reads, no downloads. Relies on evicted iCloud files still showing their
  // original filename in a directory listing on iOS.
  Future<List<Track>> _listTracksQuick(String folderPath) async {
    final dir = Directory(folderPath);
    final audioFiles = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File &&
          _audioExtensions.any(entity.path.toLowerCase().endsWith)) {
        audioFiles.add(entity);
      }
    }
    audioFiles.sort((a, b) => a.path.compareTo(b.path));

    return [
      for (var i = 0; i < audioFiles.length; i++)
        Track(
          path: audioFiles[i].path,
          title: _cleanTitle(audioFiles[i].path.split('/').last),
          trackNumber: i + 1,
        ),
    ];
  }

  Future<bool> _awaitFileAvailable(String path) async {
    final deadline = DateTime.now().add(_scanDownloadTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _bookmarks.isFileAvailable(path)) return true;
      await Future.delayed(_scanPollInterval);
    }
    return false;
  }

  Future<String?> _findArtFile(String folderPath,
      {String? firstTrackPath}) async {
    for (final name in _preferredArtFilenames) {
      final f = File('$folderPath/$name');
      if (await f.exists()) return f.path;
    }
    final dir = Directory(folderPath);
    await for (final entity in dir.list()) {
      if (entity is File &&
          _artExtensions.any(entity.path.toLowerCase().endsWith)) {
        return entity.path;
      }
    }
    if (firstTrackPath != null) {
      return await _metadata.extractArtwork(firstTrackPath);
    }
    return null;
  }

  Future<void> recordPlay(String folderPath) =>
      _db.setLastActivity(folderPath, DateTime.now());

  // Writes a track's real (file-derived) metadata and marks it as read.
  // No call site yet — for a later phase to call once a track is first
  // played after being downloaded.
  Future<void> updateTrackMetadata(String filePath,
          {required String title, required int trackNumber, String? artist}) =>
      _db.markTrackMetadataRead(filePath,
          title: title, trackNumber: trackNumber, artist: artist);

  @visibleForTesting
  static String cleanTitle(String filename) => _cleanTitle(filename);

  static String _cleanTitle(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    var name = dotIndex >= 0 ? filename.substring(0, dotIndex) : filename;
    // Strip leading track number patterns like "01 - " or "01. "
    name = name.replaceFirst(RegExp(r'^\d+[\s.\-–]+'), '');
    return name.trim();
  }

  Future<void> addTag(String folderPath, String tag) =>
      _db.addTag(folderPath, tag.trim().toLowerCase());
  Future<void> removeTag(String folderPath, String tag) =>
      _db.removeTag(folderPath, tag);
  Future<List<String>> allTags() => _db.allTags();
}
