import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/release.dart';
import 'bookmark_service.dart';
import 'database_service.dart';
import 'itunes_artwork_service.dart';
import 'metadata_service.dart';
import 'music_brainz_service.dart';

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
  final MusicBrainzService _musicBrainz;
  final ItunesArtworkService _itunesArtwork;

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
    MusicBrainzService? musicBrainz,
    Duration? scanPollInterval,
    Duration? scanDownloadTimeout,
    ItunesArtworkService? itunesArtwork,
  ])  : _db = db ?? DatabaseService.instance,
        _metadata = metadata ?? MetadataService.instance,
        _bookmarks = bookmarks ?? BookmarkService.instance,
        _musicBrainz = musicBrainz ?? MusicBrainzService.instance,
        _itunesArtwork = itunesArtwork ?? ItunesArtworkService.instance,
        _scanPollInterval = scanPollInterval ?? const Duration(seconds: 1),
        _scanDownloadTimeout =
            scanDownloadTimeout ?? const Duration(seconds: 30);

  static LibraryService get instance => _instance ??= LibraryService._();

  @visibleForTesting
  factory LibraryService.forTest(
    DatabaseService db, {
    MetadataService? metadata,
    BookmarkService? bookmarks,
    MusicBrainzService? musicBrainz,
    Duration? scanPollInterval,
    Duration? scanDownloadTimeout,
    ItunesArtworkService? itunesArtwork,
  }) =>
      LibraryService._(db, metadata, bookmarks, musicBrainz, scanPollInterval,
          scanDownloadTimeout, itunesArtwork);

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

  // Explicit, user-triggered rescan of a release that's already been
  // scanned — the file tags are treated as the source of truth, so this
  // re-reads the first track's album artist/title and re-resolves artwork
  // exactly as during initial discovery, overwriting the release's stored
  // name, album title, album artist, and art path even if something
  // different was already stored. Unlike syncLibrary, this runs regardless
  // of first_track_scanned, since the whole point is to correct a release
  // that already scanned successfully but whose file tags have since
  // changed on disk.
  Future<void> rescanRelease(String folderPath) =>
      _resolveFirstTrack(folderPath, folderPath.split('/').last);

  // Attempts to resolve album-level info (name, art, albumArtist/albumTitle)
  // from the release's first track (by sorted filename), downloading and
  // evicting it as needed. Shared by brand-new discovery and by retrying a
  // release whose first scan previously timed out — which can happen
  // repeatedly, on every sync, independent of any manual artwork retry the
  // user has already done (see the artPath fallback below). Does not touch
  // the rest of the release's track rows.
  Future<void> _resolveFirstTrack(String folderPath, String folderName) async {
    final quickTracks = await _listTracksQuick(folderPath);
    if (quickTracks.isEmpty) {
      return; // folder now empty; next sync's disk-diff will remove it
    }
    final firstTrackPath = quickTracks.first.path;

    final folderArtPath =
        await _findArtFile(folderPath); // folder-image check only — no download
    // Only download (and, below, evict) the first track if it isn't already
    // locally available — otherwise an already-downloaded release would get
    // its first track evicted by a scan/rescan purely incidental to reading
    // its tags, leaving the rest of the release downloaded but not the
    // first track.
    final wasAlreadyAvailable = await _bookmarks.isFileAvailable(firstTrackPath);
    if (!wasAlreadyAvailable) await _bookmarks.downloadFile(firstTrackPath);
    if (!await _awaitFileAvailable(firstTrackPath)) {
      // Still worth keeping any folder-image art found without a download,
      // even though the metadata read didn't happen this time. The release
      // stays unscanned either way, so it's retried on the next sync.
      if (folderArtPath != null) {
        await _db.updateArtPath(folderPath, folderArtPath);
      }
      return;
    }

    final meta = await _metadata.readMetadata(firstTrackPath);
    final albumArtist =
        meta.albumArtist?.isNotEmpty == true ? meta.albumArtist : null;
    final albumTitle =
        meta.albumTitle?.isNotEmpty == true ? meta.albumTitle : null;
    final resolvedArtPath = await _resolveArtwork(folderPath,
        knownArtPath: folderArtPath,
        albumArtist: albumArtist,
        albumTitle: albumTitle,
        downloadedFirstTrackPath: firstTrackPath,
        resolveFirstTrackArtist: () async => meta.artist);
    if (!wasAlreadyAvailable) {
      await _bookmarks.evictFile(firstTrackPath); // best-effort
    }

    // A release can stay unresolved (retried by every sync via
    // _retryUnresolvedRelease) for a reason unrelated to artwork, e.g. its
    // first-track download keeps timing out — meanwhile, a manual retry
    // (opening its release screen) can already have found and persisted
    // artwork independently. Falling back to whatever's already stored
    // when this attempt finds nothing new means a resolve attempt can
    // never erase artwork a previous one already found.
    final artPath = resolvedArtPath ??
        (await _db.loadRelease(folderPath))?['art_path'] as String?;

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

  // A single, on-demand attempt to resolve artwork for a release that still
  // has none — triggered when the release screen opens on one, or from a
  // bulk sweep on refresh. Re-downloads the first track (unless a folder
  // image is already present) so its embedded artwork gets a fresh check
  // before falling back to MusicBrainz: a first attempt during the scan can
  // fail for reasons that aren't actually deterministic, and some releases
  // are tagged with artwork that MusicBrainz has no way to find at all.
  // Returns the resolved path (already persisted to the DB), or null if
  // nothing new was found.
  Future<String?> retryArtwork(String folderPath,
      {required String? albumArtist, required String? albumTitle}) async {
    final folderArtPath = await _findArtFile(folderPath);
    final firstTrackResult = folderArtPath == null
        ? await _downloadFirstTrackForRetry(folderPath)
        : (path: null, wasAlreadyAvailable: false);
    final downloadedFirstTrackPath = firstTrackResult.path;

    AudioMetadata? firstTrackMeta;
    Future<String?> resolveFirstTrackArtist() async {
      if (downloadedFirstTrackPath == null) return null;
      firstTrackMeta ??= await _metadata.readMetadata(downloadedFirstTrackPath);
      return firstTrackMeta!.artist?.isNotEmpty == true
          ? firstTrackMeta!.artist
          : null;
    }

    final artPath = await _resolveArtwork(folderPath,
        knownArtPath: folderArtPath,
        albumArtist: albumArtist,
        albumTitle: albumTitle,
        downloadedFirstTrackPath: downloadedFirstTrackPath,
        resolveFirstTrackArtist: resolveFirstTrackArtist);

    if (downloadedFirstTrackPath != null &&
        !firstTrackResult.wasAlreadyAvailable) {
      await _bookmarks.evictFile(downloadedFirstTrackPath); // best-effort
    }
    if (artPath != null) await _db.updateArtPath(folderPath, artPath);
    return artPath;
  }

  // Re-attempts artwork for every currently-known, fully-scanned release
  // that still has none (or whose stored art_path file has gone missing on
  // disk). Only ever invoked from an explicit refresh — never automatically
  // — so a release with no findable artwork doesn't get hit repeatedly
  // without the user asking. Processed one at a time; MusicBrainz calls are
  // serialized by MusicBrainzService itself, so no extra throttling is
  // needed here. A release still going through its first-track scan this
  // same sync is skipped — it already gets its own MusicBrainz attempt via
  // the unresolved-release retry path, so retrying it again here would
  // just double up.
  //
  // onArtworkResolved fires only when a release's artwork was actually
  // found (so a caller can invalidate an image cache entry for that exact
  // path); onProgress fires for every release attempted, found or not (so
  // a caller can refresh the UI as the sweep progresses).
  //
  // A single release's own failure (e.g. its folder disappearing mid-sweep,
  // or an unexpected native-channel error) is caught rather than left to
  // propagate — otherwise it would silently abort the loop, leaving every
  // release after it in the list never even attempted.
  Future<void> retryMissingArtwork({
    void Function(String artPath)? onArtworkResolved,
    void Function()? onProgress,
  }) async {
    final rows = await _db.loadAllReleases();
    for (final row in rows) {
      if ((row['first_track_scanned'] as int) != 1) continue;
      final artPath = row['art_path'] as String?;
      if (artPath != null && File(artPath).existsSync()) continue;
      try {
        final resolved = await retryArtwork(row['folder_path'] as String,
            albumArtist: row['album_artist'] as String?,
            albumTitle: row['album_title'] as String?);
        if (resolved != null) onArtworkResolved?.call(resolved);
      } catch (_) {
        // Move on to the next release rather than losing the rest of the
        // sweep to one release's failure.
      }
      onProgress?.call();
    }
  }

  // The single place artwork is resolved from every source, in priority
  // order: a folder image file, then (only when the first track has
  // already been downloaded this call — during a scan, or by retryArtwork)
  // its embedded artwork, then a MusicBrainz lookup, then an iTunes Search
  // API lookup as a further fallback for whatever MusicBrainz can't find —
  // falling back to the track's own artist tag when no album artist is
  // known, since ripped CDs often tag the track artist (TPE1) but not the
  // album artist (TPE2). Every caller that fetches artwork goes through
  // this, so a source or fallback added here automatically covers all of
  // them — this consolidation exists because the artist-tag fallback was
  // previously duplicated per call site and silently dropped from one of
  // them during a rewrite.
  //
  // Embedded artwork is copied into the release's own folder (see
  // _persistExtractedArtwork) rather than used from wherever it was
  // extracted to, so it's stored exactly like a MusicBrainz download.
  //
  // resolveFirstTrackArtist is lazy (only awaited if actually needed, i.e.
  // no art found yet and no album artist known) since reading it requires
  // a metadata read of whatever track was already downloaded.
  Future<String?> _resolveArtwork(
    String folderPath, {
    String? knownArtPath,
    required String? albumArtist,
    required String? albumTitle,
    required Future<String?> Function() resolveFirstTrackArtist,
    String? downloadedFirstTrackPath,
  }) async {
    var artPath = knownArtPath ?? await _findArtFile(folderPath);
    if (artPath == null && downloadedFirstTrackPath != null) {
      final extracted = await _metadata.extractArtwork(downloadedFirstTrackPath);
      if (extracted != null) {
        artPath = await _persistExtractedArtwork(folderPath, extracted);
      }
    }
    if (artPath == null) {
      final searchArtist = albumArtist ?? await resolveFirstTrackArtist();
      artPath = await _musicBrainz.fetchArtwork(
          albumArtist: searchArtist,
          albumTitle: albumTitle,
          folderPath: folderPath);
      artPath ??= await _itunesArtwork.fetchArtwork(
          albumArtist: searchArtist,
          albumTitle: albumTitle,
          folderPath: folderPath);
    }
    return artPath;
  }

  // Embedded-artwork extraction (see MetadataService.extractArtwork) writes
  // the image into the app's own internal storage, not the release's
  // folder — a location that doesn't survive a fresh app install/redeploy,
  // unlike the release's folder on the user's own iCloud Drive. Copying it
  // there under the same filename a MusicBrainz download would use makes
  // it just as durable. Returns null (rather than throwing) if the copy
  // fails, so the caller falls through to a MusicBrainz lookup instead of
  // losing the artwork resolution attempt entirely.
  Future<String?> _persistExtractedArtwork(
      String folderPath, String extractedPath) async {
    try {
      final dest = File('$folderPath/cover.jpg');
      await File(extractedPath).copy(dest.path);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  // Downloads the release's first track for retryArtwork, so its embedded
  // artwork (and, if needed, its own artist tag) can be checked. Skips the
  // download (and reports wasAlreadyAvailable: true) when the track is
  // already locally available — an already-downloaded release shouldn't
  // have its first track evicted by an artwork retry incidental to it,
  // leaving the rest of the release downloaded but not the first track.
  // path is null — without downloading anything further — if the release
  // has no tracks yet, or the download doesn't become available in time.
  Future<({String? path, bool wasAlreadyAvailable})> _downloadFirstTrackForRetry(
      String folderPath) async {
    final tracks = await _db.loadTracks(folderPath);
    if (tracks.isEmpty) return (path: null, wasAlreadyAvailable: false);
    final firstTrackPath = tracks.first['file_path'] as String;
    final wasAlreadyAvailable = await _bookmarks.isFileAvailable(firstTrackPath);
    if (!wasAlreadyAvailable) await _bookmarks.downloadFile(firstTrackPath);
    if (!await _awaitFileAvailable(firstTrackPath)) {
      return (path: null, wasAlreadyAvailable: wasAlreadyAvailable);
    }
    return (path: firstTrackPath, wasAlreadyAvailable: wasAlreadyAvailable);
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
