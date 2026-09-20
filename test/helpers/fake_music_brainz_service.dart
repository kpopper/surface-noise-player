import 'package:surface_noise_player/services/music_brainz_service.dart';

class FakeMusicBrainzService implements MusicBrainzService {
  String? artPathToReturn;
  bool wasCalled = false;
  String? lastFetchedArtist;
  String? lastFetchedTitle;

  // Folder paths to simulate an unexpected failure for, e.g. to test that
  // one release's failure doesn't stop a bulk sweep from attempting the
  // rest — real callers never throw (MusicBrainzService swallows its own
  // failures), but a caller like retryMissingArtwork should still be
  // resilient to a failure from anywhere in the resolution chain.
  Set<String> throwForFolderPaths = {};

  @override
  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  }) async {
    wasCalled = true;
    lastFetchedArtist = albumArtist;
    lastFetchedTitle = albumTitle;
    if (throwForFolderPaths.contains(folderPath)) {
      throw Exception('simulated failure for $folderPath');
    }
    return artPathToReturn;
  }
}
