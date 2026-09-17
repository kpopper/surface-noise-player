import 'package:flutter/foundation.dart';
import '../models/release.dart';
import 'bookmark_service.dart';
import 'library_service.dart';

class LibraryProvider extends ChangeNotifier {
  final LibraryService _svc;
  final BookmarkService _bookmarks;
  LibraryProvider([LibraryService? svc, BookmarkService? bookmarks])
      : _svc = svc ?? LibraryService.instance,
        _bookmarks = bookmarks ?? BookmarkService.instance;

  List<Release> _releases = [];
  final List<String> _activeTags = [];
  bool loading = false;
  String? rootPath;

  List<Release> get releases {
    if (_activeTags.isEmpty) return _releases;
    return _releases
        .where((r) => _activeTags.every((t) => r.tags.contains(t)))
        .toList();
  }

  List<Release> get allReleases => _releases;
  List<String> get activeTags => List.unmodifiable(_activeTags);

  Future<void> init() async {
    final bookmarkedPath = await _bookmarks.resolveBookmark();
    rootPath = bookmarkedPath ?? await _svc.getSavedRoot();
    if (rootPath != null) {
      // Show whatever the database already knows immediately — no need to
      // wait for a sync just to display releases discovered in a previous
      // session. The sync then runs as a background refresh on top.
      await _reloadReleases();
      await _syncInBackground(rootPath!);
    }
  }

  Future<void> pickFolder() async {
    final path = await _svc.pickLibraryFolder();
    if (path != null) {
      rootPath = path;
      // A different root has nothing already loaded worth showing (picking
      // it just reset the database), so there's no "known releases" to keep
      // visible here — unlike init()/refresh() below.
      _releases = [];
      _activeTags.clear();
      await _syncInBackground(rootPath!);
    }
  }

  Future<void> refresh() async {
    if (rootPath == null) return;
    await _syncInBackground(rootPath!);
  }

  // Syncs the directory with the database, reloading the library as changes
  // are found so releases appear/disappear progressively rather than only
  // once the whole sync finishes. Already-loaded releases stay visible (and
  // tappable) the whole time — `loading` only drives the app bar's spinner,
  // not the release list.
  Future<void> _syncInBackground(String root) async {
    loading = true;
    notifyListeners();
    await _svc.syncLibrary(root, onProgress: _reloadReleases);
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
      _sortByActivity(_releases);
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
      _sortByActivity(_releases);
      notifyListeners();
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

  void clearTagFilter() {
    _activeTags.clear();
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
}
