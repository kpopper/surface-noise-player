import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class ItunesArtworkService {
  static ItunesArtworkService? _instance;
  static ItunesArtworkService get instance =>
      _instance ??= _ItunesArtworkServiceImpl();

  @visibleForTesting
  factory ItunesArtworkService.forTest(http.Client client,
          {Duration? minInterval}) =>
      _ItunesArtworkServiceImpl(client, minInterval);

  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  });
}

// A last-resort fallback for when MusicBrainz has no match, or no cover art
// for the match it found. See MusicBrainzService for the reasoning behind
// this pattern (per-call fresh client, request throttling) — the same
// mobile-networking failure modes apply regardless of which API is called.
class _ItunesArtworkServiceImpl implements ItunesArtworkService {
  // Apple's published rate limit for the Search API is ~20 calls/minute;
  // matched exactly here the same way MusicBrainzService matches its own
  // published 1 req/sec limit, since a bulk artwork sweep could otherwise
  // burst well past it across many releases in a row.
  static const _defaultMinInterval = Duration(milliseconds: 3000);

  final http.Client? _injectedClient;
  final Duration _minInterval;

  Future<void> _rateLimitGate = Future.value();

  _ItunesArtworkServiceImpl([this._injectedClient, Duration? minInterval])
      : _minInterval = minInterval ?? _defaultMinInterval;

  @override
  Future<String?> fetchArtwork({
    required String? albumArtist,
    required String? albumTitle,
    required String folderPath,
  }) async {
    if (albumArtist == null || albumTitle == null) return null;
    return _throttled(() => _attempt(albumArtist, albumTitle, folderPath));
  }

  Future<String?> _attempt(
      String albumArtist, String albumTitle, String folderPath) async {
    final client = _injectedClient ?? http.Client();
    try {
      final artworkUrl = await _search(client, albumArtist, albumTitle);
      if (artworkUrl == null) return null;
      return await _downloadArtwork(client, artworkUrl, folderPath);
    } catch (_) {
      // Never propagate — every caller treats "no artwork found" and "the
      // lookup itself failed" identically, same as MusicBrainzService.
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
        Future.delayed(_minInterval, completer.complete);
      }
    });
  }

  Future<String?> _search(
      http.Client client, String artist, String title) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': '$artist $title',
      'entity': 'album',
      'limit': '5',
    });
    final response = await client.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? [];
    if (results.isEmpty) return null;

    // Prefer a result whose album name and artist both match what we
    // searched for — the term search is fuzzy and can return an unrelated,
    // same-artist album (or a same-titled album by someone else) ahead of
    // the one actually wanted. Falls back to the top result otherwise.
    final matches = results.where((r) =>
        (r['collectionName'] as String?)?.toLowerCase() ==
            title.toLowerCase() &&
        (r['artistName'] as String?)?.toLowerCase() == artist.toLowerCase());
    final candidate = matches.isNotEmpty ? matches.first : results.first;

    final artworkUrl100 = candidate['artworkUrl100'] as String?;
    if (artworkUrl100 == null) return null;
    // artworkUrl100 points at a 100x100 thumbnail; iTunes serves any other
    // resolution from the same URL by swapping this size segment.
    return artworkUrl100.replaceFirst('100x100bb', '1200x1200bb');
  }

  Future<String?> _downloadArtwork(
      http.Client client, String artworkUrl, String folderPath) async {
    final response = await client.get(Uri.parse(artworkUrl));
    if (response.statusCode != 200) return null;
    final file = File('$folderPath/cover.jpg');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }
}
