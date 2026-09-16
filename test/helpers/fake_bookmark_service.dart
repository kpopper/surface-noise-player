import 'package:surface_noise_player/services/bookmark_service.dart';

class FakeBookmarkService implements BookmarkService {
  String? pathToReturn;
  String? lastPickedPath;
  bool downloadResult = true;
  bool downloadFileResult = true;
  bool awaitDownloadResult = true;
  String? lastDownloadPath;
  String? lastAwaitDownloadPath;
  String? lastEvictPath;
  final List<String> downloadFileCalls = [];
  Set<String> unavailablePaths = {};

  @override
  Future<String?> pickFolder() async {
    lastPickedPath = pathToReturn;
    return pathToReturn;
  }

  @override
  Future<String?> resolveBookmark() async => pathToReturn;

  @override
  Future<void> stopAccess() async {}

  @override
  Future<bool> downloadRelease(String folderPath) async {
    lastDownloadPath = folderPath;
    return downloadResult;
  }

  @override
  Future<bool> downloadFile(String path) async {
    downloadFileCalls.add(path);
    return downloadFileResult;
  }

  @override
  Future<bool> awaitDownload(String folderPath) async {
    lastAwaitDownloadPath = folderPath;
    return awaitDownloadResult;
  }

  @override
  Future<void> evictRelease(String folderPath) async {
    lastEvictPath = folderPath;
  }

  @override
  Future<bool> isFileAvailable(String path) async => !unavailablePaths.contains(path);
}
