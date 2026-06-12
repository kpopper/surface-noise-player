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
    // Resolve the security-scoped bookmark first so iOS grants directory access.
    final bookmarkedPath = await _bookmarks.resolveBookmark();
    rootPath = bookmarkedPath ?? await _svc.getSavedRoot();
    if (rootPath != null) await _quickScan();
  }

  Future<void> pickFolder() async {
    final path = await _svc.pickLibraryFolder();
    if (path != null) {
      rootPath = path;
      await _fullScan();
    }
  }

  Future<void> _quickScan() async {
    loading = true;
    notifyListeners();
    _releases = await _svc.quickScanLibrary(rootPath!, _releases);
    _sortByActivity(_releases);
    loading = false;
    notifyListeners();
  }

  Future<void> _fullScan() async {
    loading = true;
    notifyListeners();
    _releases = await _svc.scanLibrary(rootPath!);
    _sortByActivity(_releases);
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (rootPath != null) await _quickScan();
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
    final index =
        _releases.indexWhere((r) => r.folderPath == release.folderPath);
    if (index >= 0) {
      final updated =
          _releases[index].copyWith(tags: [..._releases[index].tags, tag]);
      _releases[index] = updated;
      notifyListeners();
    }
  }

  Future<void> removeTagFromRelease(Release release, String tag) async {
    await _svc.removeTag(release.folderPath, tag);
    final index =
        _releases.indexWhere((r) => r.folderPath == release.folderPath);
    if (index >= 0) {
      final updated = _releases[index].copyWith(
        tags: _releases[index].tags.where((t) => t != tag).toList(),
      );
      _releases[index] = updated;
      notifyListeners();
    }
  }

  Future<List<String>> allTags() => _svc.allTags();
}
