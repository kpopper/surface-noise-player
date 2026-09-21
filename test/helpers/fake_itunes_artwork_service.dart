import 'package:surface_noise_player/services/itunes_artwork_service.dart';

class FakeItunesArtworkService implements ItunesArtworkService {
  String? artPathToReturn;
  bool wasCalled = false;
  String? lastFetchedArtist;
  String? lastFetchedTitle;

  @override
  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  }) async {
    wasCalled = true;
    lastFetchedArtist = albumArtist;
    lastFetchedTitle = albumTitle;
    return artPathToReturn;
  }
}
