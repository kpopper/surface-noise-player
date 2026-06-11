import 'package:surface_noise_player/services/bookmark_service.dart';

class FakeBookmarkService implements BookmarkService {
  String? pathToReturn;
  String? lastPickedPath;

  @override
  Future<String?> pickFolder() async {
    lastPickedPath = pathToReturn;
    return pathToReturn;
  }

  @override
  Future<String?> resolveBookmark() async => pathToReturn;

  @override
  Future<void> stopAccess() async {}
}
