import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/library_service.dart';

/// A fully controllable in-memory stand-in for LibraryService.
class FakeLibraryService implements LibraryService {
  String? rootToReturn;
  List<Release> releasesToReturn = [];
  List<String> tagsToReturn = [];

  // Recorded calls
  String? lastAddedTagPath;
  String? lastAddedTag;
  String? lastRemovedTagPath;
  String? lastRemovedTag;
  int scanCallCount = 0;
  int quickScanCallCount = 0;

  @override
  Future<String?> getSavedRoot() async => rootToReturn;

  @override
  Future<String?> pickLibraryFolder() async => rootToReturn;

  @override
  Future<List<Release>> scanLibrary(String rootPath) async {
    scanCallCount++;
    return releasesToReturn;
  }

  @override
  Future<List<Release>> quickScanLibrary(String rootPath, List<Release> existing) async {
    quickScanCallCount++;
    return releasesToReturn;
  }

  @override
  Future<List<String>> allTags() async => tagsToReturn;

  @override
  Future<void> addTag(String folderPath, String tag) async {
    lastAddedTagPath = folderPath;
    lastAddedTag = tag;
  }

  @override
  Future<void> removeTag(String folderPath, String tag) async {
    lastRemovedTagPath = folderPath;
    lastRemovedTag = tag;
  }
}
