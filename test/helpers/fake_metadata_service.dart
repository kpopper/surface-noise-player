import 'package:surface_noise_player/services/metadata_service.dart';

class FakeMetadataService implements MetadataService {
  final Map<String, AudioMetadata> responses;

  FakeMetadataService([Map<String, AudioMetadata>? responses])
      : responses = responses ?? {};

  @override
  Future<AudioMetadata> readMetadata(String path) async =>
      responses[path] ?? AudioMetadata.empty;
}
