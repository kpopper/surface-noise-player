import 'dart:async';

import 'package:surface_noise_player/services/bookmark_service.dart';

class FakeBookmarkService implements BookmarkService {
  String? pathToReturn;

  // If set, resolveBookmark waits for this to complete before returning —
  // lets tests observe LibraryProvider's transient pre-initialized state
  // instead of it resolving synchronously within a single pump.
  Completer<void>? resolveBookmarkGate;
  String? lastPickedPath;
  bool downloadResult = true;
  bool downloadFileResult = true;
  String? lastDownloadPath;
  String? lastEvictPath;
  String? lastDownloadFilePath;
  String? lastEvictFilePath;
  final List<String> downloadFileCalls = [];
  final List<String> downloadReleaseCalls = [];
  final List<String> evictFileCalls = [];
  Set<String> unavailablePaths = {};

  // Opt-in: when true, a successful downloadFile() call removes the path
  // from unavailablePaths, simulating a download actually completing.
  // Defaults to false so tests that pre-seed unavailablePaths to simulate a
  // download that never completes (a timeout) are unaffected — set this to
  // true only for a test that wants "not yet downloaded, but succeeds once
  // requested".
  bool downloadFileGrantsAvailability = false;

  @override
  Future<String?> pickFolder() async {
    lastPickedPath = pathToReturn;
    return pathToReturn;
  }

  @override
  Future<String?> resolveBookmark() async {
    if (resolveBookmarkGate != null) await resolveBookmarkGate!.future;
    return pathToReturn;
  }

  @override
  Future<void> stopAccess() async {}

  @override
  Future<bool> downloadRelease(String folderPath) async {
    lastDownloadPath = folderPath;
    downloadReleaseCalls.add(folderPath);
    return downloadResult;
  }

  @override
  Future<void> evictRelease(String folderPath) async {
    lastEvictPath = folderPath;
  }

  @override
  Future<bool> downloadFile(String path) async {
    lastDownloadFilePath = path;
    downloadFileCalls.add(path);
    if (downloadFileResult && downloadFileGrantsAvailability) {
      unavailablePaths.remove(path);
    }
    return downloadFileResult;
  }

  @override
  Future<void> evictFile(String path) async {
    lastEvictFilePath = path;
    evictFileCalls.add(path);
    // Mirrors reality: evicting removes the local copy, so the path needs a
    // fresh download again next time — matters for a test that evicts and
    // then re-checks/re-downloads the same path within one test.
    unavailablePaths.add(path);
  }

  @override
  Future<bool> isFileAvailable(String path) async =>
      !unavailablePaths.contains(path);
}
