import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../models/release.dart';
import 'bookmark_service.dart';
import 'library_service.dart';
import 'migration_export_service.dart';

enum LibrarySortMode { recency, alphabetical }

class LibraryProvider extends ChangeNotifier {
  final LibraryService _svc;
  final BookmarkService _bookmarks;
  // TEMPORARY — see migration_export_service.dart. Remove this dependency
  // (and its call sites below) once the TestFlight migration is done.
  final MigrationExportService _migration;
  LibraryProvider(
      [LibraryService? svc,
      BookmarkService? bookmarks,
      MigrationExportService? migration])
      : _svc = svc ?? LibraryService.instance,
        _bookmarks = bookmarks ?? BookmarkService.instance,
        _migration = migration ?? MigrationExportService.instance;

  List<Release> _releases = [];
  final List<String> _activeTags = [];
  String _searchQuery = '';
  LibrarySortMode _sortMode = LibrarySortMode.recency;
  bool loading = false;
  bool initialized = false;
  String? rootPath;

  List<Release> get releases {
    var result = _releases;
    if (_activeTags.isNotEmpty) {
      result = result
          .where((r) => _activeTags.every((t) => r.tags.contains(t)))
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((r) => r.name.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  List<Release> get allReleases => _releases;
  List<String> get activeTags => List.unmodifiable(_activeTags);
  String get searchQuery => _searchQuery;
  LibrarySortMode get sortMode => _sortMode;

  Future<void> init() async {
    final bookmarkedPath = await _bookmarks.resolveBookmark();
    rootPath = bookmarkedPath ?? await _svc.getSavedRoot();
    if (rootPath != null) {
      // Show whatever the database already knows immediately — no need to
      // wait for a sync just to display releases discovered in a previous
      // session. The sync then runs as a background refresh on top.
      await _reloadReleases();
    }
    // Flips the screen from blank to its real state (release list, no-root
    // CTA, or no-releases CTA) — set once we know the answer, rather than
    // leaving the UI to guess from rootPath's initial null default while
    // this async lookup is still in flight.
    initialized = true;
    notifyListeners();
    if (rootPath != null) {
      await _syncInBackground(rootPath!);
    }
  }

  Future<void> pickFolder() async {
    final wasAlreadySet = rootPath != null;
    final path = await _svc.pickLibraryFolder();
    if (path != null) {
      rootPath = path;
      // A different root has nothing already loaded worth showing (picking
      // it just reset the database), so there's no "known releases" to keep
      // visible here — unlike init()/refresh() below.
      _releases = [];
      _activeTags.clear();
      _searchQuery = '';
      // TEMPORARY — see migration_export_service.dart. Only on a fresh
      // install (no root previously saved) so a returning user re-picking
      // their existing folder never has tags/activity silently overwritten
      // by an older export file.
      if (!wasAlreadySet) {
        await _migration.importIfPresent(rootPath!);
      }
      await _syncInBackground(rootPath!);
    }
  }

  // TEMPORARY — see migration_export_service.dart. Writes the current
  // tags/activity to the library root for a later fresh install to import.
  Future<void> exportForMigration() async {
    if (rootPath == null) return;
    await _migration.exportTo(rootPath!, _releases);
  }

  Future<void> refresh() async {
    if (rootPath == null) return;
    await _syncInBackground(rootPath!, retryMissingArt: true);
  }

  // Syncs the directory with the database, reloading the library as changes
  // are found so releases appear/disappear progressively rather than only
  // once the whole sync finishes. Already-loaded releases stay visible (and
  // tappable) the whole time — `loading` only drives the app bar's spinner,
  // not the release list.
  //
  // retryMissingArt additionally sweeps every fully-scanned release still
  // missing artwork after the regular sync — only refresh() opts into this
  // (never init()/pickFolder()), so nothing retries automatically on
  // launch, only on an explicit refresh tap.
  Future<void> _syncInBackground(String root,
      {bool retryMissingArt = false}) async {
    loading = true;
    notifyListeners();
    await _svc.syncLibrary(root, onProgress: _reloadReleases);
    if (retryMissingArt) {
      await _svc.retryMissingArtwork(
        onArtworkResolved: (artPath) =>
            PaintingBinding.instance.imageCache.evict(FileImage(File(artPath))),
        onProgress: _reloadReleases,
      );
    }
    await _reloadReleases(); // catch-all, in case the last progress tick raced this
    loading = false;
    notifyListeners();
  }

  // syncLibrary's onProgress can fire many times in quick succession (e.g.
  // several releases finishing concurrently) — coalesce overlapping calls
  // into a single reload instead of piling up redundant full-library
  // queries, while still guaranteeing one more reload after the busy one
  // finishes so the latest state is never missed.
  bool _reloadInFlight = false;
  bool _reloadPending = false;

  Future<void> _reloadReleases() async {
    if (_reloadInFlight) {
      _reloadPending = true;
      return;
    }
    _reloadInFlight = true;
    do {
      _reloadPending = false;
      _releases = await _svc.loadLibrary();
      _applySort(_releases);
      notifyListeners();
    } while (_reloadPending);
    _reloadInFlight = false;
  }

  Future<void> recordPlay(String folderPath) async {
    await _svc.recordPlay(folderPath);
    final index = _releases.indexWhere((r) => r.folderPath == folderPath);
    if (index >= 0) {
      _releases[index] =
          _releases[index].copyWith(lastActivityAt: DateTime.now());
      // Re-sorting is a no-op in alphabetical mode (it doesn't depend on
      // activity), but harmless to always call — keeps this one call site
      // correct regardless of which mode is currently active.
      _applySort(_releases);
      notifyListeners();
    }
  }

  void toggleSortMode() {
    _sortMode = _sortMode == LibrarySortMode.recency
        ? LibrarySortMode.alphabetical
        : LibrarySortMode.recency;
    _applySort(_releases);
    notifyListeners();
  }

  void _applySort(List<Release> releases) {
    switch (_sortMode) {
      case LibrarySortMode.recency:
        _sortByActivity(releases);
      case LibrarySortMode.alphabetical:
        releases.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  void _sortByActivity(List<Release> releases) {
    releases.sort((a, b) {
      final aTime = a.lastActivityAt;
      final bTime = b.lastActivityAt;
      if (aTime == null && bTime == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
  }

  void toggleTag(String tag) {
    if (_activeTags.contains(tag)) {
      _activeTags.remove(tag);
    } else {
      _activeTags.add(tag);
    }
    notifyListeners();
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  Future<void> addTagToRelease(Release release, String tag) async {
    await _svc.addTag(release.folderPath, tag);
    final index =
        _releases.indexWhere((r) => r.folderPath == release.folderPath);
    if (index >= 0) {
      _releases[index] =
          _releases[index].copyWith(tags: [..._releases[index].tags, tag]);
      notifyListeners();
    }
  }

  Future<void> removeTagFromRelease(Release release, String tag) async {
    await _svc.removeTag(release.folderPath, tag);
    final index =
        _releases.indexWhere((r) => r.folderPath == release.folderPath);
    if (index >= 0) {
      _releases[index] = _releases[index].copyWith(
        tags: _releases[index].tags.where((t) => t != tag).toList(),
      );
      notifyListeners();
    }
  }

  Future<List<String>> allTags() => _svc.allTags();

  // Persists a track's freshly-read metadata (see PlayerService) and updates
  // the in-memory copy so a release screen watching this provider reflects
  // it immediately, without waiting for a sync.
  Future<void> updateTrackMetadata(String folderPath, Track track) async {
    await _svc.updateTrackMetadata(track.path,
        title: track.title,
        trackNumber: track.trackNumber,
        artist: track.artist);
    final index = _releases.indexWhere((r) => r.folderPath == folderPath);
    if (index < 0) return;
    final release = _releases[index];
    final trackIndex = release.tracks.indexWhere((t) => t.path == track.path);
    if (trackIndex < 0) return;
    final updatedTracks = [...release.tracks];
    updatedTracks[trackIndex] = track;
    _releases[index] = Release(
      folderPath: release.folderPath,
      name: release.name,
      tracks: updatedTracks,
      tags: release.tags,
      artPath: release.artPath,
      albumTitle: release.albumTitle,
      albumArtist: release.albumArtist,
      lastActivityAt: release.lastActivityAt,
    );
    notifyListeners();
  }

  // Called once by ReleaseScreen when it opens on a release with no
  // artwork. No-ops (and doesn't touch the service) if the release already
  // has art, so it's safe to call defensively. Returns whether artwork was
  // newly found, so a caller can report success/failure.
  Future<bool> retryArtworkIfMissing(Release release) async {
    if (release.artPath != null) return false;
    final artPath = await _svc.retryArtwork(release.folderPath,
        albumArtist: release.albumArtist, albumTitle: release.albumTitle);
    if (artPath == null) return false;
    // Flutter's image cache is keyed by file path, not content — without
    // this, a path that was already rendered once this session (e.g. the
    // same cover.jpg filename, now holding a freshly-resolved image) would
    // keep showing whatever was cached for that path instead of the new
    // bytes.
    PaintingBinding.instance.imageCache.evict(FileImage(File(artPath)));
    final index =
        _releases.indexWhere((r) => r.folderPath == release.folderPath);
    if (index >= 0) {
      _releases[index] = _releases[index].copyWith(artPath: artPath);
      notifyListeners();
    }
    return true;
  }

  // Explicit, user-triggered rescan of a release from its release screen —
  // e.g. after correcting the file tags on disk. Reloads the whole library
  // afterwards (same as a sync) so the release's name/album title/artist
  // and artwork pick up whatever the rescan found.
  Future<void> rescanRelease(Release release) async {
    final oldArtPath = release.artPath;
    await _svc.rescanRelease(release.folderPath);
    await _reloadReleases();
    final index =
        _releases.indexWhere((r) => r.folderPath == release.folderPath);
    final newArtPath = index >= 0 ? _releases[index].artPath : null;
    // Flutter's image cache is keyed by file path, not content — evict both
    // the old and new paths so neither keeps showing stale cached bytes.
    if (oldArtPath != null) {
      PaintingBinding.instance.imageCache.evict(FileImage(File(oldArtPath)));
    }
    if (newArtPath != null && newArtPath != oldArtPath) {
      PaintingBinding.instance.imageCache.evict(FileImage(File(newArtPath)));
    }
  }
}
