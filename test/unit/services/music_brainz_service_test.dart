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

  test('retries once and succeeds after a transient network failure', () async {
    const releaseGroupId = 'group-retry';
    var callCount = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        callCount++;
        if (callCount == 1) {
          throw const SocketException('connection reset');
        }
        return http.Response(
            jsonEncode({
              'releases': [
                {
                  'title': 'Goo',
                  'date': '1990',
                  'release-group': {'id': releaseGroupId},
                },
              ],
            }),
            200);
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Sonic Youth',
      albumTitle: 'Goo',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
    expect(callCount, 2);
  });

  test('retries once and succeeds after a transient 5xx search response',
      () async {
    // Regression: a 503 from the search endpoint (confirmed on-device,
    // gone on the very next attempt) was being treated identically to a
    // genuine "no match" — a non-200 response never threw, so the
    // retry-on-exception logic never saw it.
    const releaseGroupId = 'group-retry-503';
    var callCount = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        callCount++;
        if (callCount == 1) {
          return http.Response('Service Unavailable', 503);
        }
        return http.Response(
            jsonEncode({
              'releases': [
                {
                  'title': 'Five Leaves Left',
                  'date': '1969',
                  'release-group': {'id': releaseGroupId},
                },
              ],
            }),
            200);
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Nick Drake',
      albumTitle: 'Five Leaves Left',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
    expect(callCount, 2);
  });

  test('succeeds on the third attempt after two consecutive 503s', () async {
    // Regression: on-device testing during a bulk sweep saw the *same*
    // release (the last of 5 in the batch) get two 503s in a row — a
    // single retry (2 attempts total) wasn't always enough.
    const releaseGroupId = 'group-retry-twice';
    var callCount = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        callCount++;
        if (callCount <= 2) {
          return http.Response('Service Unavailable', 503);
        }
        return http.Response(
            jsonEncode({
              'releases': [
                {
                  'title': 'Tromatic Reflexxions',
                  'date': '2007',
                  'release-group': {'id': releaseGroupId},
                },
              ],
            }),
            200);
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Von Südenfed',
      albumTitle: 'Tromatic Reflexxions',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
    expect(callCount, 3);
  });

  test('does not retry a 404 from the cover art archive (a real not-found)',
      () async {
    var coverArtCallCount = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(
            jsonEncode({
              'releases': [
                {
                  'title': 'Some Album',
                  'date': '2020',
                  'release-group': {'id': 'group-no-art'},
                },
              ],
            }),
            200);
      }
      coverArtCallCount++;
      return http.Response('Not Found', 404);
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Some Artist',
      albumTitle: 'Some Album',
      folderPath: tempDir.path,
    );

    expect(artPath, isNull);
    expect(coverArtCallCount, 1); // not retried — a 404 isn't transient
  });

  test('gives up after the retry also fails', () async {
    final client = MockClient((request) async {
      throw const SocketException('connection reset');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Sonic Youth',
      albumTitle: 'Goo',
      folderPath: tempDir.path,
    );

    expect(artPath, isNull);
  });

  test(
      'serializes concurrent lookups with at least minInterval between requests',
      () async {
    final requestTimes = <DateTime>[];
    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        requestTimes.add(DateTime.now());
        return http.Response(jsonEncode({'releases': []}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final service = MusicBrainzService.forTest(client,
        minInterval: const Duration(milliseconds: 200));

    await Future.wait([
      service.fetchArtwork(
          albumArtist: 'Artist A',
          albumTitle: 'Album A',
          folderPath: tempDir.path),
      service.fetchArtwork(
          albumArtist: 'Artist B',
          albumTitle: 'Album B',
          folderPath: tempDir.path),
    ]);

    expect(requestTimes.length, 2);
    expect(requestTimes[1].difference(requestTimes[0]).inMilliseconds,
        greaterThanOrEqualTo(200));
  });

  test('retries without a leading "The " when the exact match is empty',
      () async {
    // Regression: The Secret Machines' "Ten Silver Drops" is credited on
    // MusicBrainz to plain "Secret Machines" — the exact quoted artist
    // search for "The Secret Machines" matches nothing, so a search
    // without the "The" should be tried as a fallback.
    const releaseGroupId = 'secret-machines-group';
    final queries = <String>[];
    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        final query = request.url.queryParameters['query']!;
        queries.add(query);
        if (query.contains('"The Secret Machines"')) {
          return http.Response(jsonEncode({'releases': []}), 200);
        }
        return http.Response(
            jsonEncode({
              'releases': [
                {
                  'title': 'Ten Silver Drops',
                  'date': '2006',
                  'release-group': {'id': releaseGroupId},
                },
              ],
            }),
            200);
      }
      if (request.url.host == 'coverartarchive.org') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'The Secret Machines',
      albumTitle: 'Ten Silver Drops',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
    expect(queries, [
      'artist:"The Secret Machines" AND release:"Ten Silver Drops"',
      'artist:"Secret Machines" AND release:"Ten Silver Drops"',
    ]);
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

  test(
      'prefers an Album release-group over a same-titled single or EP by '
      'the same artist', () async {
    // Regression: Clinic released a 7" single titled "Walking With Thee" a
    // week ahead of the album of the same name — both share the exact
    // title, so the earliest-date tiebreak alone picked the single's
    // release-group, which the Cover Art Archive has no scan for, over the
    // album's, which does.
    const singleGroupId = 'walking-with-thee-single';
    const albumGroupId = 'walking-with-thee-album';
    final searchResponse = jsonEncode({
      'releases': [
        {
          'title': 'Walking With Thee',
          'date': '2002-02-18', // earlier than the album
          'release-group': {'id': singleGroupId, 'primary-type': 'Single'},
        },
        {
          'title': 'Walking With Thee',
          'date': '2002-02-25',
          'release-group': {'id': albumGroupId, 'primary-type': 'Album'},
        },
      ],
    });

    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(searchResponse, 200);
      }
      if (request.url.host == 'coverartarchive.org') {
        expect(request.url.path, '/release-group/$albumGroupId/front-1200');
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Clinic',
      albumTitle: 'Walking With Thee',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
  });

  test(
      'falls back to the earliest date among all candidates when none is '
      'typed as an Album', () async {
    const epGroupId = 'some-ep';
    final searchResponse = jsonEncode({
      'releases': [
        {
          'title': 'Some EP',
          'date': '1999-01-01',
          'release-group': {'id': epGroupId, 'primary-type': 'EP'},
        },
      ],
    });

    final client = MockClient((request) async {
      if (request.url.host == 'musicbrainz.org') {
        return http.Response(searchResponse, 200);
      }
      if (request.url.host == 'coverartarchive.org') {
        expect(request.url.path, '/release-group/$epGroupId/front-1200');
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected request to ${request.url}');
    });

    final service = MusicBrainzService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Some Artist',
      albumTitle: 'Some EP',
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
