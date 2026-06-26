import 'package:flutter/foundation.dart';
import '../models/folder_info.dart';
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
      loading = true;
      notifyListeners();
      _releases = await _svc.loadSelectedReleases();
      _sortByActivity(_releases);
      loading = false;
      notifyListeners();
      // Fire-and-forget background tasks.
      _refreshDownloadState();
      _refreshArtwork();
    }
  }

  Future<void> pickFolder() async {
    final path = await _svc.pickLibraryFolder();
    if (path != null) {
      rootPath = path;
      _releases = [];
      _activeTags.clear();
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (rootPath == null) return;
    loading = true;
    notifyListeners();
    for (final release in _releases) {
      await _svc.rescanRelease(release.folderPath);
    }
    _releases = await _svc.loadSelectedReleases();
    _sortByActivity(_releases);
    loading = false;
    notifyListeners();
  }

  Future<List<FolderInfo>> listAllFolders() async {
    if (rootPath == null) return [];
    return _svc.listAllFolders(rootPath!);
  }

  Future<void> selectRelease(String folderPath) async {
    // Wait for all files to be locally available before scanning for metadata.
    final downloaded = await _bookmarks.awaitDownload(folderPath);
    final release = await _svc.selectRelease(folderPath);
    if (release == null) return;
    if (downloaded) {
      _releases.add(release);
    } else {
      _releases.add(release.copyWith(isAvailable: false));
      // Download timed out — watch in background and mark available when ready.
      _awaitAndMarkAvailable(folderPath);
    }
    _sortByActivity(_releases);
    notifyListeners();
  }

  Future<void> _awaitAndMarkAvailable(String folderPath) async {
    final downloaded = await _bookmarks.awaitDownload(folderPath);
    if (!downloaded) return;
    final index = _releases.indexWhere((r) => r.folderPath == folderPath);
    if (index < 0) return; // was deselected in the meantime
    final updated = await _svc.selectRelease(folderPath);
    if (updated == null) return;
    _releases[index] = updated;
    _sortByActivity(_releases);
    notifyListeners();
  }

  Future<void> deselectRelease(String folderPath) async {
    await _svc.deselectRelease(folderPath);
    await _bookmarks.evictRelease(folderPath);
    _releases.removeWhere((r) => r.folderPath == folderPath);
    notifyListeners();
  }

  Future<void> _refreshArtwork() async {
    var changed = false;
    for (var i = 0; i < _releases.length; i++) {
      if (_releases[i].artPath != null) continue;
      final artPath = await _svc.refreshArtwork(_releases[i].folderPath);
      if (artPath != null) {
        final r = _releases[i];
        _releases[i] = Release(
          folderPath: r.folderPath,
          name: r.name,
          tracks: r.tracks,
          tags: r.tags,
          artPath: artPath,
          albumTitle: r.albumTitle,
          albumArtist: r.albumArtist,
          lastActivityAt: r.lastActivityAt,
          isAvailable: r.isAvailable,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _refreshDownloadState() async {
    var changed = false;
    for (var i = 0; i < _releases.length; i++) {
      final available = await _bookmarks.downloadRelease(_releases[i].folderPath);
      if (_releases[i].isAvailable != available) {
        _releases[i] = _releases[i].copyWith(isAvailable: available);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> recordPlay(String folderPath) async {
    await _svc.recordPlay(folderPath);
    final index = _releases.indexWhere((r) => r.folderPath == folderPath);
    if (index >= 0) {
      _releases[index] = _releases[index].copyWith(lastActivityAt: DateTime.now());
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
    final index = _releases.indexWhere((r) => r.folderPath == release.folderPath);
    if (index >= 0) {
      _releases[index] = _releases[index].copyWith(tags: [..._releases[index].tags, tag]);
      notifyListeners();
    }
  }

  Future<void> removeTagFromRelease(Release release, String tag) async {
    await _svc.removeTag(release.folderPath, tag);
    final index = _releases.indexWhere((r) => r.folderPath == release.folderPath);
    if (index >= 0) {
      _releases[index] = _releases[index].copyWith(
        tags: _releases[index].tags.where((t) => t != tag).toList(),
      );
      notifyListeners();
    }
  }

  Future<List<String>> allTags() => _svc.allTags();
}
