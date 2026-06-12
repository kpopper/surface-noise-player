import 'package:surface_noise_player/services/metadata_service.dart';

class FakeMetadataService implements MetadataService {
  final Map<String, AudioMetadata> responses;
  final Map<String, String> artworkPaths;

  FakeMetadataService({
    Map<String, AudioMetadata>? responses,
    Map<String, String>? artworkPaths,
  })  : responses = responses ?? {},
        artworkPaths = artworkPaths ?? {};

  @override
  Future<AudioMetadata> readMetadata(String path) async =>
      responses[path] ?? AudioMetadata.empty;

  @override
  Future<String?> extractArtwork(String path) async => artworkPaths[path];
}
