import 'package:flutter/services.dart';

abstract class BookmarkService {
  static BookmarkService? _instance;
  static BookmarkService get instance => _instance ??= _BookmarkServiceImpl();

  // Shows the native folder picker and creates a persistent bookmark in one step.
  Future<String?> pickFolder();

  // Resolves the saved bookmark on app launch and starts security-scoped access.
  Future<String?> resolveBookmark();

  // Stops security-scoped access (call on app pause / after scan completes).
  Future<void> stopAccess();

  // Requests iCloud download of all files in a folder. Returns false if the
  // request fails (e.g. insufficient storage). Returns immediately without
  // waiting for the download to complete — use awaitDownload for that.
  Future<bool> downloadRelease(String folderPath);

  // Triggers iCloud download of all files in a folder and waits until they are
  // all locally available. Returns false on timeout or if the trigger fails.
  // Used before scanning a newly selected release.
  Future<bool> awaitDownload(String folderPath);

  // Evicts all files in a folder from local iCloud storage. Best-effort.
  Future<void> evictRelease(String folderPath);

  // Checks whether a single file is available locally right now (downloaded,
  // or not iCloud-backed at all) without triggering a download.
  Future<bool> isFileAvailable(String path);
}

class _BookmarkServiceImpl implements BookmarkService {
  static const _channel = MethodChannel('com.yourname.surface_noise_player/bookmarks');
  String? _activePath;

  @override
  Future<String?> pickFolder() async {
    try {
      final path = await _channel.invokeMethod<String>('pickFolder');
      if (path != null) _activePath = path;
      return path;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> resolveBookmark() async {
    try {
      final path = await _channel.invokeMethod<String>('resolveBookmark');
      if (path != null) _activePath = path;
      return path;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> stopAccess() async {
    if (_activePath != null) {
      await _channel.invokeMethod('stopAccess', _activePath);
      _activePath = null;
    }
  }

  @override
  Future<bool> downloadRelease(String folderPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('downloadRelease', {'path': folderPath});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> awaitDownload(String folderPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('awaitDownload', {'path': folderPath});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> evictRelease(String folderPath) async {
    try {
      await _channel.invokeMethod('evictRelease', {'path': folderPath});
    } on PlatformException {
      // best-effort
    }
  }

  @override
  Future<bool> isFileAvailable(String path) async {
    try {
      final result = await _channel.invokeMethod<bool>('isFileAvailable', {'path': path});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
