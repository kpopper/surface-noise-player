import 'package:flutter/services.dart';

class AudioMetadata {
  final String? title;
  final String? artist;
  final String? albumTitle;
  final String? albumArtist;
  final int? trackNumber;

  const AudioMetadata({
    this.title,
    this.artist,
    this.albumTitle,
    this.albumArtist,
    this.trackNumber,
  });

  static const empty = AudioMetadata();
}

abstract class MetadataService {
  static MetadataService? _instance;
  static MetadataService get instance => _instance ??= _MetadataServiceImpl();

  Future<AudioMetadata> readMetadata(String path);
}

class _MetadataServiceImpl implements MetadataService {
  static const _channel = MethodChannel('com.yourname.surface_noise_player/bookmarks');

  @override
  Future<AudioMetadata> readMetadata(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'readMetadata',
        {'path': path},
      );
      if (result == null) return AudioMetadata.empty;
      return AudioMetadata(
        title: result['title'] as String?,
        artist: result['artist'] as String?,
        albumTitle: result['albumTitle'] as String?,
        albumArtist: result['albumArtist'] as String?,
        trackNumber: result['trackNumber'] as int?,
      );
    } catch (_) {
      return AudioMetadata.empty;
    }
  }
}
