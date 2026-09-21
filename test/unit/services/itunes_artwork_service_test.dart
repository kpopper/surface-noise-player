import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:surface_noise_player/services/itunes_artwork_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('itunes_artwork_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('fetches and upscales artwork for a matching result', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'itunes.apple.com') {
        return http.Response(
            jsonEncode({
              'results': [
                {
                  'collectionName': 'Goo',
                  'artistName': 'Sonic Youth',
                  'artworkUrl100':
                      'https://is1-ssl.mzstatic.com/image/thumb/goo/100x100bb.jpg',
                },
              ],
            }),
            200);
      }
      expect(request.url.toString(), contains('1200x1200bb'));
      return http.Response.bytes([1, 2, 3], 200);
    });

    final service = ItunesArtworkService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Sonic Youth',
      albumTitle: 'Goo',
      folderPath: tempDir.path,
    );

    expect(artPath, '${tempDir.path}/cover.jpg');
    expect(await File(artPath!).readAsBytes(), [1, 2, 3]);
  });

  test('prefers a result matching both artist and album name over the top result',
      () async {
    final client = MockClient((request) async {
      if (request.url.host == 'itunes.apple.com') {
        return http.Response(
            jsonEncode({
              'results': [
                {
                  'collectionName': 'A Different Album',
                  'artistName': 'Sonic Youth',
                  'artworkUrl100': 'https://example.com/wrong/100x100bb.jpg',
                },
                {
                  'collectionName': 'Goo',
                  'artistName': 'Sonic Youth',
                  'artworkUrl100': 'https://example.com/right/100x100bb.jpg',
                },
              ],
            }),
            200);
      }
      expect(request.url.toString(), contains('/right/'));
      return http.Response.bytes([1, 2, 3], 200);
    });

    final service = ItunesArtworkService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Sonic Youth',
      albumTitle: 'Goo',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
  });

  test('falls back to the top result when nothing matches exactly', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'itunes.apple.com') {
        return http.Response(
            jsonEncode({
              'results': [
                {
                  'collectionName': 'Goo (Deluxe Edition)',
                  'artistName': 'Sonic Youth',
                  'artworkUrl100': 'https://example.com/100x100bb.jpg',
                },
              ],
            }),
            200);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });

    final service = ItunesArtworkService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Sonic Youth',
      albumTitle: 'Goo',
      folderPath: tempDir.path,
    );

    expect(artPath, isNotNull);
  });

  test('returns null when the search finds nothing', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'results': []}), 200);
    });

    final service = ItunesArtworkService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Nobody',
      albumTitle: 'Nothing',
      folderPath: tempDir.path,
    );

    expect(artPath, isNull);
  });

  test('returns null instead of throwing on a network failure', () async {
    final client = MockClient((request) async {
      throw const SocketException('connection reset');
    });

    final service = ItunesArtworkService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: 'Sonic Youth',
      albumTitle: 'Goo',
      folderPath: tempDir.path,
    );

    expect(artPath, isNull);
  });

  test('returns null without a network call when artist or title is missing',
      () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response(jsonEncode({'results': []}), 200);
    });

    final service = ItunesArtworkService.forTest(client);
    final artPath = await service.fetchArtwork(
      albumArtist: null,
      albumTitle: 'Goo',
      folderPath: tempDir.path,
    );

    expect(artPath, isNull);
    expect(called, isFalse);
  });

  test(
      'serializes concurrent lookups with at least minInterval between requests',
      () async {
    final requestTimes = <DateTime>[];
    final client = MockClient((request) async {
      if (request.url.host == 'itunes.apple.com') {
        requestTimes.add(DateTime.now());
        return http.Response(jsonEncode({'results': []}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final service = ItunesArtworkService.forTest(client,
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
}
