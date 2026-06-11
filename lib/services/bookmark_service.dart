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
}
