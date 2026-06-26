import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

abstract class MusicBrainzService {
  static MusicBrainzService? _instance;
  static MusicBrainzService get instance => _instance ??= _MusicBrainzServiceImpl();

  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  });
}

class _MusicBrainzServiceImpl implements MusicBrainzService {
  static const _userAgent =
      'SurfaceNoisePlayer/1.0 (https://github.com/kpopper/surface-noise-player)';

  final http.Client _client;

  _MusicBrainzServiceImpl([http.Client? client]) : _client = client ?? http.Client();

  @override
  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  }) async {
    if (albumArtist == null || albumTitle == null) return null;
    try {
      final mbid = await _searchRelease(albumArtist, albumTitle);
      if (mbid == null) return null;
      return await _downloadArtwork(mbid, folderPath);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _searchRelease(String artist, String title) async {
    final query = 'artist:"${_escape(artist)}" release:"${_escape(title)}"';
    final uri = Uri.https('musicbrainz.org', '/ws/2/release', {
      'query': query,
      'fmt': 'json',
      'limit': '5',
    });
    final response = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return null;

    // Prefer the earliest release date (original over reissues).
    final withDates = releases
        .where((r) => (r['date'] as String?)?.isNotEmpty == true)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    final candidate = withDates.isNotEmpty ? withDates.first : releases.first;
    return candidate['id'] as String?;
  }

  Future<String?> _downloadArtwork(String mbid, String folderPath) async {
    final uri = Uri.https('coverartarchive.org', '/release/$mbid/front-1200');
    final response = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return null;

    final file = File('$folderPath/cover.jpg');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  String _escape(String s) => s.replaceAll('"', '\\"');
}
