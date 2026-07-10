import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class MusicBrainzService {
  static MusicBrainzService? _instance;
  static MusicBrainzService get instance => _instance ??= _MusicBrainzServiceImpl();

  @visibleForTesting
  factory MusicBrainzService.forTest(http.Client client) => _MusicBrainzServiceImpl(client);

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
      final releaseGroupId = await _searchReleaseGroup(albumArtist, albumTitle);
      if (releaseGroupId == null) return null;
      return await _downloadArtwork(releaseGroupId, folderPath);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _searchReleaseGroup(String artist, String title) async {
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

    // Prefer the earliest release date (original over reissues) to identify
    // the release group; individual editions within a group vary in whether
    // the Cover Art Archive has a scan, but a release-group lookup below
    // resolves to any edition that has one.
    final withDates = releases
        .where((r) => (r['date'] as String?)?.isNotEmpty == true)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    final candidate = withDates.isNotEmpty ? withDates.first : releases.first;
    return (candidate['release-group'] as Map<String, dynamic>?)?['id'] as String?;
  }

  Future<String?> _downloadArtwork(String releaseGroupId, String folderPath) async {
    final uri = Uri.https('coverartarchive.org', '/release-group/$releaseGroupId/front-1200');
    final response = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return null;

    final file = File('$folderPath/cover.jpg');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  String _escape(String s) => s.replaceAll('"', '\\"');
}
