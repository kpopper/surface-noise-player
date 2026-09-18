import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class MusicBrainzService {
  static MusicBrainzService? _instance;
  static MusicBrainzService get instance =>
      _instance ??= _MusicBrainzServiceImpl();

  @visibleForTesting
  factory MusicBrainzService.forTest(http.Client client) =>
      _MusicBrainzServiceImpl(client);

  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  });
}

class _MusicBrainzServiceImpl implements MusicBrainzService {
  static const _userAgent =
      'SurfaceNoisePlayer/1.0 (https://github.com/kpopper/surface-noise-player)';

  // Only set in tests (via forTest) — a fake/mock client that should be
  // reused, not closed. Real usage creates and closes a fresh client per
  // call instead of holding one for the app's whole lifetime; a long-lived
  // client can end up reusing a dead keep-alive connection after sitting
  // idle for a while (very plausible on mobile, across backgrounding and
  // network changes), causing every request to fail until the app
  // restarts and gets a fresh client — exactly the pattern seen testing
  // this on-device (repeated failures within one session, immediate
  // success after a restart).
  final http.Client? _injectedClient;

  _MusicBrainzServiceImpl([this._injectedClient]);

  @override
  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  }) async {
    if (albumArtist == null || albumTitle == null) return null;
    final client = _injectedClient ?? http.Client();
    try {
      final releaseGroupId =
          await _searchReleaseGroup(client, albumArtist, albumTitle);
      if (releaseGroupId == null) return null;
      return await _downloadArtwork(client, releaseGroupId, folderPath);
    } catch (_) {
      return null;
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  Future<String?> _searchReleaseGroup(
      http.Client client, String artist, String title) async {
    // Explicit AND: Lucene-style query parsers (which this search service
    // uses) default to OR between clauses, so without it this would match
    // any release by the artist, not only ones titled like the one we
    // want — which is exactly how a search for "Lowedges" once returned a
    // different, earlier Richard Hawley album ("Late Night Final") instead.
    final query = 'artist:"${_escape(artist)}" AND release:"${_escape(title)}"';
    final uri = Uri.https('musicbrainz.org', '/ws/2/release', {
      'query': query,
      'fmt': 'json',
      'limit': '5',
    });
    final response = await client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return null;

    // Prefer results whose title actually matches what we searched for —
    // a further safety net against the search still being fuzzy/stemmed
    // even with AND — before picking among them by date. Falls back to the
    // full list when no result carries a matching (or any) title.
    final titleMatches = releases
        .where((r) =>
            (r['title'] as String?)?.toLowerCase() == title.toLowerCase())
        .toList();
    final candidates = titleMatches.isNotEmpty ? titleMatches : releases;

    // Prefer the earliest release date (original over reissues) to identify
    // the release group; individual editions within a group vary in whether
    // the Cover Art Archive has a scan, but a release-group lookup below
    // resolves to any edition that has one.
    final withDates = candidates
        .where((r) => (r['date'] as String?)?.isNotEmpty == true)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    final candidate = withDates.isNotEmpty ? withDates.first : candidates.first;
    return (candidate['release-group'] as Map<String, dynamic>?)?['id']
        as String?;
  }

  Future<String?> _downloadArtwork(
      http.Client client, String releaseGroupId, String folderPath) async {
    final uri = Uri.https(
        'coverartarchive.org', '/release-group/$releaseGroupId/front-1200');
    final response = await client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return null;

    final file = File('$folderPath/cover.jpg');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  String _escape(String s) => s.replaceAll('"', '\\"');
}
