import 'package:surface_noise_player/models/folder_info.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/library_service.dart';

class FakeLibraryService implements LibraryService {
  String? rootToReturn;
  List<Release> releasesToReturn = [];
  List<String> tagsToReturn = [];
  List<FolderInfo> foldersToReturn = [];
  Release? releaseToReturnForSelect;

  // Recorded calls
  String? lastAddedTagPath;
  String? lastAddedTag;
  String? lastRemovedTagPath;
  String? lastRemovedTag;
  String? lastSelectedPath;
  String? lastDeselectedPath;
  String? lastRecordedPlayPath;
  int loadSelectedCallCount = 0;
  List<String> rescannedPaths = [];

  @override
  Future<String?> getSavedRoot() async => rootToReturn;

  @override
  Future<String?> pickLibraryFolder() async => rootToReturn;

  @override
  Future<List<Release>> loadSelectedReleases() async {
    loadSelectedCallCount++;
    return releasesToReturn;
  }

  @override
  Future<Release?> selectRelease(String folderPath) async {
    lastSelectedPath = folderPath;
    return releaseToReturnForSelect;
  }

  @override
  Future<void> deselectRelease(String folderPath) async {
    lastDeselectedPath = folderPath;
  }

  @override
  Future<List<FolderInfo>> listAllFolders(String rootPath) async {
    return foldersToReturn;
  }

  @override
  Future<void> recordPlay(String folderPath) async {
    lastRecordedPlayPath = folderPath;
  }

  @override
  Future<void> rescanRelease(String folderPath) async {
    rescannedPaths.add(folderPath);
  }

  @override
  Future<String?> refreshArtwork(String folderPath) async => null;

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
