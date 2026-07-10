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

  test('falls back to release-group artwork when the earliest-dated edition has none', () async {
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
