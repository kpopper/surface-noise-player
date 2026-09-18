import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:surface_noise_player/services/music_brainz_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('music_brainz_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
      'falls back to release-group artwork when the earliest-dated edition has none',
      () async {
    // Mirrors "Millions Now Living Will Never Die" by Tortoise: the search
    // returns several editions of the same release group, the earliest-dated
    // one (chosen by the date tiebreak) has no scan in the Cover Art
    // Archive, but a sibling edition in the same group does.
    const releaseGroupId = 'group-1';
    final searchResponse = jsonEncode({
      'releases': [
        {
          'id': 'release-early-no-art',
          'date': '1996',
          'release-group': {'id': releaseGroupId},
        },
        {
          'id': 'release-later-has-art',
          'date': '1996-01-30',
          'release-group': {'id': releaseGroupId},
        },
      ],
    });

    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(searchResponse, 200);
      }
      if (request.url.host == 'coverartarchive.org') {
        expect(request.url.path, '/release-group/$releaseGroupId/front-1200');
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Tortoise',
      albumTitle: 'Millions Now Living Will Never Die',
      folderPath: tempDir.path,
    );

    expect(artPath, '${tempDir.path}/cover.jpg');
    expect(await File(artPath!).readAsBytes(), [1, 2, 3]);
  });

  test(
      'ignores an earlier-dated release with a different title by the same artist',
      () async {
    // Regression: a search for Richard Hawley's "Lowedges" (2003) once
    // returned artwork for his earlier, differently-titled album "Late
    // Night Final" (2001) instead — the "prefer earliest date" tiebreak
    // was being applied across genuinely different albums, not just
    // editions of the one actually searched for.
    const wrongGroupId = 'late-night-final-group';
    const correctGroupId = 'lowedges-group';
    final searchResponse = jsonEncode({
      'releases': [
        {
          'id': 'late-night-final',
          'title': 'Late Night Final',
          'date': '2001',
          'release-group': {'id': wrongGroupId},
        },
        {
          'id': 'lowedges',
          'title': 'Lowedges',
          'date': '2003',
          'release-group': {'id': correctGroupId},
        },
      ],
    });

    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(searchResponse, 200);
      }
      if (request.url.host == 'coverartarchive.org') {
        expect(request.url.path, '/release-group/$correctGroupId/front-1200');
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Richard Hawley',
      albumTitle: 'Lowedges',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
  });

  test('queries with an explicit AND between artist and release clauses',
      () async {
    Uri? capturedUri;
    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        capturedUri = request.url;
        return http.Response(jsonEncode({'releases': []}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final service = MusicBrainzService.forTest(client);
    await service.fetchArtwork(
      albumArtist: 'Richard Hawley',
      albumTitle: 'Lowedges',
      folderPath: tempDir.path,
    );

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['query'], contains(' AND '));
  });

  test('returns null when the release group has no cover art at all', () async {
    final searchResponse = jsonEncode({
      'releases': [
        {
          'id': 'release-1',
          'date': '2020',
          'release-group': {'id': 'group-2'},
        },
      ],
    });

    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(searchResponse, 200);
      }
      return http.Response('Not Found', 404);
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Some Artist',
      albumTitle: 'Some Album',
      folderPath: tempDir.path,
    );

    expect(artPath, isNull);
  });
}
