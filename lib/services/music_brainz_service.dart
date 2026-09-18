import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class MusicBrainzService {
  static MusicBrainzService? _instance;
  static MusicBrainzService get instance =>
      _instance ??= _MusicBrainzServiceImpl();

  @visibleForTesting
  factory MusicBrainzService.forTest(http.Client client,
          {Duration? minInterval}) =>
      _MusicBrainzServiceImpl(client, minInterval);

  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  });
}

class _MusicBrainzServiceImpl implements MusicBrainzService {
  static const _userAgent =
      'SurfaceNoisePlayer/1.0 (https://github.com/kpopper/surface-noise-player)';
  static const _defaultMinInterval = Duration(seconds: 1);

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
  final Duration _minInterval;

  // Chains every call after the previous one's completion plus
  // _minInterval, so no two requests start closer together than that no
  // matter how many callers are racing to call fetchArtwork concurrently —
  // the scan's bounded-concurrency task pool, a bulk artwork-retry sweep,
  // and an on-demand single retry could all call this at once, and this
  // service is a singleton shared by all of them.
  Future<void> _rateLimitGate = Future.value();

  _MusicBrainzServiceImpl([this._injectedClient, Duration? minInterval])
      : _minInterval = minInterval ?? _defaultMinInterval;

  @override
  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  }) async {
    if (albumArtist == null || albumTitle == null) return null;
    return _throttled(() => _attempt(albumArtist, albumTitle, folderPath, 1));
  }

  static const _maxAttempts = 3;
  static const _baseRetryDelay = Duration(milliseconds: 500);

  // A network-level failure (dropped connection, brief DNS hiccup, a
  // transient 5xx) throws and was previously treated identically to a
  // clean "nothing found" — on-device testing showed the same release,
  // with the same stored metadata, failing on one attempt and succeeding
  // moments later on another, which a deterministic query can't explain
  // on its own. Retrying here, with a fresh client and increasing backoff
  // between attempts, fixes that directly rather than just making the
  // failure more visible. Up to 2 retries (3 attempts total): on-device
  // testing during a bulk sweep saw the *same* release get two 503s in a
  // row (the last of 5 in the batch, i.e. likely hitting the server while
  // still under load from the previous 4) — a single retry wasn't always
  // enough, but a lone request done a bit later succeeded first try.
  // Does NOT retry a clean null (no exception) — that's a real "not
  // found" (empty search results, no cover in the archive), which
  // retrying can't fix.
  Future<String?> _attempt(String albumArtist, String albumTitle,
      String folderPath, int attemptNumber) async {
    final client = _injectedClient ?? http.Client();
    try {
      final releaseGroupId =
          await _searchReleaseGroup(client, albumArtist, albumTitle);
      if (releaseGroupId == null) return null;
      return await _downloadArtwork(client, releaseGroupId, folderPath);
    } catch (_) {
      if (attemptNumber < _maxAttempts) {
        // Increasing backoff (500ms, then 1000ms) gives a server under
        // sustained load more time to recover between attempts.
        await Future.delayed(_baseRetryDelay * attemptNumber);
        return _attempt(albumArtist, albumTitle, folderPath, attemptNumber + 1);
      }
      return null;
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  Future<T> _throttled<T>(Future<T> Function() action) {
    final gate = _rateLimitGate;
    final completer = Completer<void>();
    _rateLimitGate = completer.future;
    return gate.then((_) async {
      try {
        return await action();
      } finally {
        // Not awaited — only a second, already-queued caller is held back
        // by this; the current call's own result returns immediately.
        Future.delayed(_minInterval, completer.complete);
      }
    });
  }

  Future<String?> _searchReleaseGroup(
      http.Client client, String artist, String title) async {
    final result = await _search(client, artist, title);
    if (result != null) return result;
    // Tags commonly include a leading "The " even when MusicBrainz's
    // canonical artist credit omits it (e.g. The Secret Machines' "Ten
    // Silver Drops" is credited to plain "Secret Machines") — the exact
    // quoted artist clause wouldn't match that, so retry without it if the
    // first search came up empty.
    if (artist.toLowerCase().startsWith('the ')) {
      return _search(client, artist.substring(4), title);
    }
    return null;
  }

  Future<String?> _search(
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
    // A 5xx is a transient server-side problem (confirmed on-device: a 503
    // from this exact endpoint, gone on the very next attempt) — throw so
    // it goes through _attempt's existing retry-on-exception path, rather
    // than silently returning null and being treated the same as a
    // genuine "no match" (empty results, or a real 4xx).
    if (response.statusCode >= 500) {
      throw HttpException(
          'MusicBrainz search returned HTTP ${response.statusCode}');
    }
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
    // Same reasoning as _search's 5xx handling above.
    if (response.statusCode >= 500) {
      throw HttpException(
          'Cover Art Archive returned HTTP ${response.statusCode}');
    }
    if (response.statusCode != 200) return null;

    final file = File('$folderPath/cover.jpg');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  String _escape(String s) => s.replaceAll('"', '\\"');
}
