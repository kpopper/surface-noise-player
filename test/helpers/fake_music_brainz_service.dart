import 'package:surface_noise_player/services/music_brainz_service.dart';

class FakeMusicBrainzService implements MusicBrainzService {
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
