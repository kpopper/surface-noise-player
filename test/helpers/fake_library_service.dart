import 'dart:async';

import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/library_service.dart';

class FakeLibraryService implements LibraryService {
  String? rootToReturn;
  List<Release> releasesToReturn = [];
  List<String> tagsToReturn = [];

  // If set, syncLibrary waits for this to complete before returning — lets
  // tests observe the transient "loading" state instead of it resolving
  // synchronously within a single pump.
  Completer<void>? syncGate;

  // Captured from the most recent syncLibrary call, so a test can simulate
  // a mid-sync progress tick (e.g. a release being discovered) by calling
  // triggerProgress() while syncGate is still pending.
  void Function()? _capturedOnProgress;
  void triggerProgress() => _capturedOnProgress?.call();

  // Recorded calls
  String? lastAddedTagPath;
  String? lastAddedTag;
  String? lastRemovedTagPath;
  String? lastRemovedTag;
  String? lastRecordedPlayPath;
  int loadLibraryCallCount = 0;
  List<String> syncedRoots = [];

  @override
  Future<String?> getSavedRoot() async => rootToReturn;

  @override
  Future<String?> pickLibraryFolder() async => rootToReturn;

  @override
  Future<void> syncLibrary(String rootPath,
      {void Function()? onProgress}) async {
    syncedRoots.add(rootPath);
    _capturedOnProgress = onProgress;
    if (syncGate != null) await syncGate!.future;
  }

  @override
  Future<List<Release>> loadLibrary() async {
    loadLibraryCallCount++;
    return releasesToReturn;
  }

  @override
  Future<void> recordPlay(String folderPath) async {
    lastRecordedPlayPath = folderPath;
  }

  @override
  Future<void> updateTrackMetadata(String filePath,
      {required String title,
      required int trackNumber,
      String? artist}) async {}

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
