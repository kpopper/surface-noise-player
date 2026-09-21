import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/database_service.dart';
import 'package:surface_noise_player/services/library_service.dart';
import 'package:surface_noise_player/services/metadata_service.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_metadata_service.dart';
import '../../helpers/fake_music_brainz_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('cleanTitle', () {
    test('strips file extension', () {
      expect(LibraryService.cleanTitle('Song.mp3'), 'Song');
    });

    test('strips leading track number with dash', () {
      expect(LibraryService.cleanTitle('01 - Song Title.flac'), 'Song Title');
    });

    test('strips leading track number with dot', () {
      expect(LibraryService.cleanTitle('02. Another Song.mp3'), 'Another Song');
    });

    test('strips leading track number with space only', () {
      expect(LibraryService.cleanTitle('03 Third Track.m4a'), 'Third Track');
    });

    test('strips leading track number with en-dash', () {
      expect(LibraryService.cleanTitle('04 – En Dash Title.aiff'),
          'En Dash Title');
    });

    test('does not strip number from middle of title', () {
      expect(LibraryService.cleanTitle('Song 2 Reprise.mp3'), 'Song 2 Reprise');
    });

    test('handles filename with no extension', () {
      expect(LibraryService.cleanTitle('01 - NoExt'), 'NoExt');
    });

    test('trims surrounding whitespace', () {
      expect(LibraryService.cleanTitle('  My Song.mp3  '), 'My Song');
    });
  });

  group('syncLibrary', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late FakeMetadataService fakeMetadata;
    late FakeBookmarkService fakeBookmarks;
    late FakeMusicBrainzService fakeMusicBrainz;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_sync_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      fakeMetadata = FakeMetadataService();
      fakeBookmarks = FakeBookmarkService();
      fakeMusicBrainz = FakeMusicBrainzService();
      service = LibraryService.forTest(
        dbService,
        metadata: fakeMetadata,
        bookmarks: fakeBookmarks,
        musicBrainz: fakeMusicBrainz,
        scanPollInterval: Duration.zero,
        scanDownloadTimeout: const Duration(milliseconds: 50),
      );
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    Future<Directory> createAlbum(
        String name, List<String> trackFilenames) async {
      final dir = await Directory('${tempRoot.path}/$name').create();
      for (final filename in trackFilenames) {
        await File('${dir.path}/$filename').create();
      }
      return dir;
    }

    group('new releases', () {
      test('creates a release row for a subfolder with audio files', () async {
        await createAlbum(
            'My Album', ['01 - Track One.mp3', '02 - Track Two.mp3']);
        await service.syncLibrary(tempRoot.path);
        expect(
            await dbService.allReleasePaths(), ['${tempRoot.path}/My Album']);
      });

      test('creates filename-derived track rows in filename order', () async {
        final albumDir = await createAlbum('Album', ['02.mp3', '01.mp3']);
        await service.syncLibrary(tempRoot.path);
        final tracks = await dbService.loadTracks(albumDir.path);
        expect(tracks.map((t) => t['file_path']).toList(),
            ['${albumDir.path}/01.mp3', '${albumDir.path}/02.mp3']);
      });

      test('strips leading track number prefixes for the track title',
          () async {
        final albumDir = await createAlbum('Album', ['01 - Hello World.mp3']);
        await service.syncLibrary(tempRoot.path);
        final tracks = await dbService.loadTracks(albumDir.path);
        expect(tracks.first['title'], 'Hello World');
      });

      test('assigns an activity timestamp at discovery time', () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        final before = DateTime.now().subtract(const Duration(seconds: 1));
        await service.syncLibrary(tempRoot.path);
        final activities = await dbService.allLastActivities();
        expect(activities[albumDir.path], isNotNull);
        expect(activities[albumDir.path]!.isAfter(before), isTrue);
      });

      test('ignores a subfolder with no audio files', () async {
        await Directory('${tempRoot.path}/Empty').create();
        await service.syncLibrary(tempRoot.path);
        expect(await dbService.allReleasePaths(), isEmpty);
      });

      test('ignores a subfolder whose name starts with underscore', () async {
        await createAlbum('_zips', ['leftover.mp3']);
        await service.syncLibrary(tempRoot.path);
        expect(await dbService.allReleasePaths(), isEmpty);
      });

      test('ignores non-audio files when listing tracks', () async {
        final albumDir = await createAlbum('Album', ['01.mp3', 'notes.txt']);
        await File('${albumDir.path}/cover.jpg').create();
        await service.syncLibrary(tempRoot.path);
        expect((await dbService.loadTracks(albumDir.path)).length, 1);
      });

      test('downloads only the first track, not every track', () async {
        final albumDir =
            await createAlbum('Album', ['01.mp3', '02.mp3', '03.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        await service.syncLibrary(tempRoot.path);
        expect(fakeBookmarks.downloadFileCalls.length, 1);
        expect(fakeBookmarks.downloadFileCalls.first, endsWith('01.mp3'));
      });

      test('evicts the first track after reading its metadata', () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        fakeBookmarks.downloadFileGrantsAvailability = true;
        await service.syncLibrary(tempRoot.path);
        expect(fakeBookmarks.evictFileCalls.length, 1);
        expect(fakeBookmarks.evictFileCalls.first, endsWith('01.mp3'));
      });

      test('marks the release as scanned once the first track resolves',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        await service.syncLibrary(tempRoot.path);
        expect(await dbService.unscannedReleasePaths(),
            isNot(contains(albumDir.path)));
      });

      test(
          'reads albumArtist/albumTitle from the first track into the release row',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'The Artist', albumTitle: 'Great Album');
        await service.syncLibrary(tempRoot.path);
        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['album_artist'], 'The Artist');
        expect(row['album_title'], 'Great Album');
        expect(row['name'], 'The Artist - Great Album');
      });

      test('does not persist the first track\'s own title/artist during a scan',
          () async {
        // Regression: the first-track read that resolves album-level
        // name/art was also writing its real title/artist/trackNumber back
        // to that one track's row, so it showed corrected metadata while
        // every other track in the release still showed its filename guess
        // — metadata should stay filename-derived for every track,
        // including the first, until it's actually played.
        final albumDir = await createAlbum('Album', ['01 - Filename.mp3']);
        fakeMetadata.responses['${albumDir.path}/01 - Filename.mp3'] =
            const AudioMetadata(title: 'Real Title', artist: 'Real Artist');
        await service.syncLibrary(tempRoot.path);
        final track = (await dbService.loadTracks(albumDir.path)).first;
        expect(track['title'], 'Filename');
        expect(track['artist'], isNull);
        expect(track['metadata_read'], 0);
      });

      test('release name falls back to folder name when metadata is absent',
          () async {
        final albumDir = await createAlbum('My Folder Name', ['01.mp3']);
        await service.syncLibrary(tempRoot.path);
        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['name'], 'My Folder Name');
      });

      test(
          'finds folder-image artwork without needing the first track to download',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        await File('${albumDir.path}/cover.jpg').create();
        fakeBookmarks.unavailablePaths = {
          '${albumDir.path}/01.mp3'
        }; // never downloads
        await service.syncLibrary(tempRoot.path);
        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['art_path'], '${albumDir.path}/cover.jpg');
      });

      test(
          'falls back to embedded artwork only after the first track becomes available',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        // Outside the release's own folder — a file living there would be
        // picked up by _findArtFile as if it were a real folder image,
        // short-circuiting before embedded-artwork extraction is even
        // attempted.
        final extractedPath = '${tempRoot.path}/extracted.jpg';
        await File(extractedPath).writeAsBytes([1, 2, 3]);
        fakeMetadata.artworkPaths['${albumDir.path}/01.mp3'] = extractedPath;
        await service.syncLibrary(tempRoot.path);
        final row = await dbService.loadRelease(albumDir.path);
        // Copied into the release's own folder, not left at wherever it was
        // extracted to — see _persistExtractedArtwork.
        expect(row!['art_path'], '${albumDir.path}/cover.jpg');
      });

      test(
          'falls back to MusicBrainz when no folder image or embedded artwork is found',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'The Artist', albumTitle: 'Great Album');
        fakeMusicBrainz.artPathToReturn = '${albumDir.path}/cover.jpg';
        await service.syncLibrary(tempRoot.path);
        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['art_path'], '${albumDir.path}/cover.jpg');
        expect(fakeMusicBrainz.lastFetchedArtist, 'The Artist');
        expect(fakeMusicBrainz.lastFetchedTitle, 'Great Album');
      });

      test(
          'falls back to the track artist tag for MusicBrainz when album artist is absent',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            artist: 'Track Artist', albumTitle: 'Great Album');
        await service.syncLibrary(tempRoot.path);
        expect(fakeMusicBrainz.wasCalled, isTrue);
        expect(fakeMusicBrainz.lastFetchedArtist, 'Track Artist');
      });

      test(
          'does not call MusicBrainz when folder-image artwork was already found',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        await File('${albumDir.path}/cover.jpg').create();
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'The Artist', albumTitle: 'Great Album');
        await service.syncLibrary(tempRoot.path);
        expect(fakeMusicBrainz.wasCalled, isFalse);
      });

      test(
          'artPath stays null when no art is found and the first track times out',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeMetadata.artworkPaths['${albumDir.path}/01.mp3'] =
            '/tmp/extracted.jpg';
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        await service.syncLibrary(tempRoot.path);
        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['art_path'], isNull);
      });

      test(
          'when the first-track download times out, the release is still created',
          () async {
        final albumDir =
            await createAlbum('Timeout Album', ['01.mp3', '02.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        await service.syncLibrary(tempRoot.path);

        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['name'], 'Timeout Album'); // folder-name fallback
        expect(row['first_track_scanned'], 0);
        expect(fakeBookmarks.evictFileCalls, isEmpty);
        final tracks = await dbService.loadTracks(albumDir.path);
        expect(tracks.length, 2); // filename-derived tracks still created
      });

      test(
          'two releases discovered in the same sync each resolve their own first track',
          () async {
        final albumA = await createAlbum('Album A', ['01.mp3']);
        final albumB = await createAlbum('Album B', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {
          '${albumA.path}/01.mp3',
          '${albumB.path}/01.mp3',
        };
        fakeBookmarks.downloadFileGrantsAvailability = true;
        fakeMetadata.responses['${albumA.path}/01.mp3'] =
            const AudioMetadata(albumTitle: 'A');
        fakeMetadata.responses['${albumB.path}/01.mp3'] =
            const AudioMetadata(albumTitle: 'B');

        await service.syncLibrary(tempRoot.path);

        expect((await dbService.loadRelease(albumA.path))!['album_title'], 'A');
        expect((await dbService.loadRelease(albumB.path))!['album_title'], 'B');
        expect(fakeBookmarks.downloadFileCalls,
            containsAll(['${albumA.path}/01.mp3', '${albumB.path}/01.mp3']));
      });
    });

    group('removed releases', () {
      test('removes a release whose folder no longer exists on disk', () async {
        await dbService.saveRelease('${tempRoot.path}/Gone', 'Gone Album');
        await service.syncLibrary(tempRoot.path);
        expect(await dbService.loadRelease('${tempRoot.path}/Gone'), isNull);
      });

      test('removes the tracks for a removed release', () async {
        final path = '${tempRoot.path}/Gone';
        await dbService.saveRelease(path, 'Gone Album');
        await dbService.saveTracks(path, [
          const Track(path: '/gone/01.mp3', title: 'Track', trackNumber: 1)
        ]);
        await service.syncLibrary(tempRoot.path);
        expect(await dbService.loadTracks(path), isEmpty);
      });

      test('preserves tags for a removed release', () async {
        final path = '${tempRoot.path}/Gone';
        await dbService.saveRelease(path, 'Gone Album');
        await dbService.addTag(path, 'jazz');
        await service.syncLibrary(tempRoot.path);
        expect(await dbService.tagsForRelease(path), ['jazz']);
      });

      test('preserves activity for a removed release', () async {
        final path = '${tempRoot.path}/Gone';
        final t = DateTime(2025, 1, 1);
        await dbService.saveRelease(path, 'Gone Album');
        await dbService.setLastActivity(path, t);
        await service.syncLibrary(tempRoot.path);
        final activities = await dbService.allLastActivities();
        expect(activities[path], t);
      });
    });

    group('unchanged releases', () {
      test('an already-scanned release still on disk is left untouched',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'Original', albumTitle: 'Original Album');
        await service.syncLibrary(
            tempRoot.path); // first sync: discovers and resolves it

        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'Changed', albumTitle: 'Changed Album');
        fakeBookmarks.downloadFileCalls.clear();
        await service
            .syncLibrary(tempRoot.path); // second sync: should not re-scan

        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['album_artist'], 'Original');
        expect(row['album_title'], 'Original Album');
        expect(fakeBookmarks.downloadFileCalls, isEmpty);
      });
    });

    group('retrying unresolved releases', () {
      test('a release whose first scan timed out is retried on the next sync',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'Artist', albumTitle: 'Album Title');
        await service.syncLibrary(tempRoot.path); // times out
        expect(
            (await dbService
                .loadRelease(albumDir.path))!['first_track_scanned'],
            0);

        fakeBookmarks.unavailablePaths = {}; // now available
        await service.syncLibrary(tempRoot.path); // retried

        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['first_track_scanned'], 1);
        expect(row['album_artist'], 'Artist');
        expect(row['album_title'], 'Album Title');
      });

      test('a release that keeps timing out stays unresolved and unchanged',
          () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        await service.syncLibrary(tempRoot.path);
        await service.syncLibrary(tempRoot.path); // still times out

        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['first_track_scanned'], 0);
        expect(row['name'], 'Album'); // still folder-name fallback
      });

      test(
          'does not erase artwork a manual retry already found while still '
          'unresolved', () async {
        // Regression: a release can stay unresolved indefinitely for a
        // reason unrelated to artwork (its first-track download keeps
        // timing out), which meant every sync re-ran _resolveFirstTrack and
        // unconditionally overwrote art_path with whatever that attempt
        // found — including null — silently erasing artwork a manual
        // on-demand retry had already found and persisted independently.
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        await service.syncLibrary(tempRoot.path); // times out, stays unresolved

        fakeBookmarks.unavailablePaths = {}; // retryArtwork's download works
        fakeMusicBrainz.artPathToReturn = '${albumDir.path}/cover.jpg';
        await service.retryArtwork(albumDir.path,
            albumArtist: 'Artist', albumTitle: 'Title');
        expect((await dbService.loadRelease(albumDir.path))!['art_path'],
            '${albumDir.path}/cover.jpg');

        // The next sync retries the still-unresolved release again; this
        // time nothing new is found at all (no folder image, no embedded
        // artwork, and — simulating a real "not found" — no MusicBrainz
        // match either).
        fakeMusicBrainz.artPathToReturn = null;
        await service.syncLibrary(tempRoot.path);

        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['first_track_scanned'], 1);
        expect(row['art_path'], '${albumDir.path}/cover.jpg');
      });
    });

    group('rescanRelease', () {
      test('overwrites a previously stored name, album title, and artist '
          'with freshly-read tags', () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'Original', albumTitle: 'Original Album [UK]');
        await service.syncLibrary(tempRoot.path); // first scan

        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'Original', albumTitle: 'Original Album');
        await service.rescanRelease(albumDir.path);

        final row = await dbService.loadRelease(albumDir.path);
        expect(row!['album_title'], 'Original Album');
        expect(row['name'], 'Original - Original Album');
      });

      test('re-resolves artwork using the corrected tags', () async {
        // Regression case: a release's first scan found no artwork because
        // the stale tag didn't match anything on MusicBrainz; after the
        // file's tag is corrected, a rescan should search again rather than
        // being stuck with the earlier not-found result.
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'Artist', albumTitle: 'Wrong Title');
        fakeMusicBrainz.artPathToReturn = null;
        await service.syncLibrary(tempRoot.path); // first scan finds nothing
        expect((await dbService.loadRelease(albumDir.path))!['art_path'], null);

        fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(
            albumArtist: 'Artist', albumTitle: 'Correct Title');
        fakeMusicBrainz.artPathToReturn = '${albumDir.path}/cover.jpg';
        await service.rescanRelease(albumDir.path);

        expect((await dbService.loadRelease(albumDir.path))!['art_path'],
            '${albumDir.path}/cover.jpg');
      });

      test('downloads and evicts the first track again', () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        fakeBookmarks.downloadFileGrantsAvailability = true;
        await service.syncLibrary(tempRoot.path);
        fakeBookmarks.downloadFileCalls.clear();
        fakeBookmarks.evictFileCalls.clear();

        await service.rescanRelease(albumDir.path);

        expect(fakeBookmarks.downloadFileCalls, ['${albumDir.path}/01.mp3']);
        expect(fakeBookmarks.evictFileCalls, ['${albumDir.path}/01.mp3']);
      });

      test(
          'does not evict the first track when it was already downloaded '
          'before the rescan', () async {
        // Regression: rescanning an already-fully-downloaded release used to
        // evict its first track purely as a side effect of reading its
        // tags, leaving the rest of the release downloaded but not the
        // first track — jarring for a release the user otherwise kept
        // downloaded.
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        fakeBookmarks.downloadFileGrantsAvailability = true;
        await service.syncLibrary(tempRoot.path);
        // The first track is available again by the time of the rescan
        // (e.g. it was re-downloaded, or never actually evicted elsewhere).
        fakeBookmarks.unavailablePaths = {};
        fakeBookmarks.downloadFileCalls.clear();
        fakeBookmarks.evictFileCalls.clear();

        await service.rescanRelease(albumDir.path);

        expect(fakeBookmarks.downloadFileCalls, isEmpty);
        expect(fakeBookmarks.evictFileCalls, isEmpty);
      });

      test('leaves first_track_scanned set', () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        await service.syncLibrary(tempRoot.path);

        await service.rescanRelease(albumDir.path);

        expect((await dbService.loadRelease(albumDir.path))!['first_track_scanned'],
            1);
      });
    });

    group('combined', () {
      test(
          'adds, removes, retries, and leaves unchanged releases in a single call',
          () async {
        final unchanged = await createAlbum('Unchanged', ['01.mp3']);
        final unresolved = await createAlbum('Unresolved', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${unresolved.path}/01.mp3'};
        await service.syncLibrary(
            tempRoot.path); // seeds unchanged (resolved) + unresolved

        await dbService.saveRelease(
            '${tempRoot.path}/Removed', 'Removed Album'); // not on disk
        final added = await createAlbum('Added', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {}; // let the retry succeed this time

        await service.syncLibrary(tempRoot.path);

        final paths = await dbService.allReleasePaths();
        expect(
            paths, containsAll([unchanged.path, unresolved.path, added.path]));
        expect(paths, isNot(contains('${tempRoot.path}/Removed')));
        expect(
            (await dbService
                .loadRelease(unresolved.path))!['first_track_scanned'],
            1);
      });
    });

    group('onProgress', () {
      test('is called once per newly discovered release', () async {
        await createAlbum('Album A', ['01.mp3']);
        await createAlbum('Album B', ['01.mp3']);
        var calls = 0;
        await service.syncLibrary(tempRoot.path, onProgress: () => calls++);
        expect(calls, 2);
      });

      test('is called once per removed release', () async {
        await dbService.saveRelease('${tempRoot.path}/Gone', 'Gone Album');
        var calls = 0;
        await service.syncLibrary(tempRoot.path, onProgress: () => calls++);
        expect(calls, 1);
      });

      test('is called once per retried release, resolved or not', () async {
        final albumDir = await createAlbum('Album', ['01.mp3']);
        fakeBookmarks.unavailablePaths = {'${albumDir.path}/01.mp3'};
        await service.syncLibrary(tempRoot.path); // discovers, times out

        var calls = 0;
        await service.syncLibrary(tempRoot.path, onProgress: () => calls++);
        expect(calls, 1); // retried, still times out
      });

      test('is not called for an already-scanned release left untouched',
          () async {
        await createAlbum('Album', ['01.mp3']);
        await service.syncLibrary(tempRoot.path); // discovers and resolves it

        var calls = 0;
        await service.syncLibrary(tempRoot.path, onProgress: () => calls++);
        expect(calls, 0);
      });
    });
  });

  group('retryArtwork', () {
    late Directory tempDir;
    late DatabaseService dbService;
    late FakeMetadataService fakeMetadata;
    late FakeBookmarkService fakeBookmarks;
    late FakeMusicBrainzService fakeMusicBrainz;
    late LibraryService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('snp_art_retry_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      fakeMetadata = FakeMetadataService();
      fakeBookmarks = FakeBookmarkService();
      fakeMusicBrainz = FakeMusicBrainzService();
      service = LibraryService.forTest(
        dbService,
        metadata: fakeMetadata,
        bookmarks: fakeBookmarks,
        musicBrainz: fakeMusicBrainz,
        scanPollInterval: Duration.zero,
        scanDownloadTimeout: const Duration(milliseconds: 50),
      );
      await dbService.saveRelease(tempDir.path, 'Some Album');
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempDir.delete(recursive: true);
    });

    test('finds a newly-added folder image without calling MusicBrainz',
        () async {
      await File('${tempDir.path}/cover.jpg').create();
      final result = await service.retryArtwork(tempDir.path,
          albumArtist: 'Artist', albumTitle: 'Title');
      expect(result, '${tempDir.path}/cover.jpg');
      expect(fakeMusicBrainz.wasCalled, isFalse);
      final row = await dbService.loadRelease(tempDir.path);
      expect(row!['art_path'], '${tempDir.path}/cover.jpg');
    });

    test('falls back to MusicBrainz when no folder image exists', () async {
      fakeMusicBrainz.artPathToReturn = '${tempDir.path}/cover.jpg';
      final result = await service.retryArtwork(tempDir.path,
          albumArtist: 'Artist', albumTitle: 'Title');
      expect(result, '${tempDir.path}/cover.jpg');
      expect(fakeMusicBrainz.lastFetchedArtist, 'Artist');
      expect(fakeMusicBrainz.lastFetchedTitle, 'Title');
      final row = await dbService.loadRelease(tempDir.path);
      expect(row!['art_path'], '${tempDir.path}/cover.jpg');
    });

    test('returns null and leaves the DB row untouched when nothing is found',
        () async {
      final result = await service.retryArtwork(tempDir.path,
          albumArtist: 'Artist', albumTitle: 'Title');
      expect(result, isNull);
      final row = await dbService.loadRelease(tempDir.path);
      expect(row!['art_path'], isNull);
    });

    test(
        'falls back to the first track\'s own artist tag when no album artist is known',
        () async {
      // Regression: ripped CDs often only tag the track artist (TPE1), not
      // the album artist (TPE2) — the initial scan already falls back to
      // it, but that read isn't kept around for a later retry to reuse.
      await dbService.saveTracks(tempDir.path, [
        Track(
            path: '${tempDir.path}/01.mp3', title: 'Track One', trackNumber: 1),
      ]);
      fakeBookmarks.unavailablePaths = {'${tempDir.path}/01.mp3'};
      fakeBookmarks.downloadFileGrantsAvailability = true;
      fakeMetadata.responses['${tempDir.path}/01.mp3'] =
          const AudioMetadata(artist: 'Track Artist');
      fakeMusicBrainz.artPathToReturn = '${tempDir.path}/cover.jpg';

      final result = await service.retryArtwork(tempDir.path,
          albumArtist: null, albumTitle: 'Title');

      expect(result, '${tempDir.path}/cover.jpg');
      expect(fakeMusicBrainz.lastFetchedArtist, 'Track Artist');
      expect(fakeBookmarks.evictFileCalls, ['${tempDir.path}/01.mp3']);
    });

    test(
        'does not evict the first track when it was already downloaded',
        () async {
      // Same regression as rescanRelease's: an artwork retry on an
      // already-downloaded release shouldn't evict its first track purely
      // as a side effect of checking embedded artwork.
      await dbService.saveTracks(tempDir.path, [
        Track(
            path: '${tempDir.path}/01.mp3', title: 'Track One', trackNumber: 1),
      ]);
      final extractedPath = '${tempDir.path}_embedded.jpg';
      await File(extractedPath).writeAsBytes([1, 2, 3]);
      fakeMetadata.artworkPaths['${tempDir.path}/01.mp3'] = extractedPath;

      final result = await service.retryArtwork(tempDir.path,
          albumArtist: 'Artist', albumTitle: 'Title');

      expect(result, '${tempDir.path}/cover.jpg'); // still resolved
      expect(fakeBookmarks.downloadFileCalls, isEmpty);
      expect(fakeBookmarks.evictFileCalls, isEmpty);
    });

    test(
        'does not re-download the first track when a folder image is already found',
        () async {
      await File('${tempDir.path}/cover.jpg').create();
      await dbService.saveTracks(tempDir.path, [
        Track(
            path: '${tempDir.path}/01.mp3', title: 'Track One', trackNumber: 1),
      ]);

      await service.retryArtwork(tempDir.path,
          albumArtist: null, albumTitle: 'Title');

      expect(fakeBookmarks.downloadFileCalls, isEmpty);
    });

    test(
        'downloads the first track to check its embedded artwork even when '
        'an album artist is already known', () async {
      await dbService.saveTracks(tempDir.path, [
        Track(
            path: '${tempDir.path}/01.mp3', title: 'Track One', trackNumber: 1),
      ]);
      fakeBookmarks.unavailablePaths = {'${tempDir.path}/01.mp3'};

      await service.retryArtwork(tempDir.path,
          albumArtist: 'Artist', albumTitle: 'Title');

      expect(fakeBookmarks.downloadFileCalls, ['${tempDir.path}/01.mp3']);
    });

    test(
        'finds embedded artwork on the first track without calling '
        'MusicBrainz', () async {
      // A scan's own embedded-artwork extraction can fail for reasons that
      // aren't actually deterministic (or, before this fix, retryArtwork
      // never checked it at all) — a retry re-downloads the first track and
      // gives it a fresh chance before falling back to MusicBrainz.
      await dbService.saveTracks(tempDir.path, [
        Track(
            path: '${tempDir.path}/01.mp3', title: 'Track One', trackNumber: 1),
      ]);
      fakeBookmarks.unavailablePaths = {'${tempDir.path}/01.mp3'};
      fakeBookmarks.downloadFileGrantsAvailability = true;
      // Outside the release's own folder — a file living there would be
      // picked up by _findArtFile as if it were a real folder image,
      // short-circuiting before embedded-artwork extraction is even
      // attempted.
      final extractedPath = '${tempDir.path}_embedded.jpg';
      await File(extractedPath).writeAsBytes([1, 2, 3]);
      fakeMetadata.artworkPaths['${tempDir.path}/01.mp3'] = extractedPath;

      final result = await service.retryArtwork(tempDir.path,
          albumArtist: 'Artist', albumTitle: 'Title');

      // Copied into the release's own folder, not left at wherever it was
      // extracted to — see _persistExtractedArtwork.
      expect(result, '${tempDir.path}/cover.jpg');
      expect(fakeMusicBrainz.wasCalled, isFalse);
      expect(fakeBookmarks.evictFileCalls, ['${tempDir.path}/01.mp3']);
      final row = await dbService.loadRelease(tempDir.path);
      expect(row!['art_path'], '${tempDir.path}/cover.jpg');
    });
  });

  group('retryMissingArtwork', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late FakeMusicBrainzService fakeMusicBrainz;
    late LibraryService service;

    setUp(() async {
      tempRoot =
          await Directory.systemTemp.createTemp('snp_bulk_art_retry_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      fakeMusicBrainz = FakeMusicBrainzService();
      service = LibraryService.forTest(dbService, musicBrainz: fakeMusicBrainz);
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    Future<Directory> makeRelease(String name,
        {String? artPath,
        String? albumArtist,
        String? albumTitle,
        bool scanned = true}) async {
      final dir = await Directory('${tempRoot.path}/$name').create();
      await dbService.saveRelease(dir.path, name,
          artPath: artPath, albumArtist: albumArtist, albumTitle: albumTitle);
      if (scanned) await dbService.markFirstTrackScanned(dir.path);
      return dir;
    }

    test('finds artwork via folder image for a release with none', () async {
      final release = await makeRelease('Album',
          albumArtist: 'Artist', albumTitle: 'Title');
      await File('${release.path}/cover.jpg').create();

      await service.retryMissingArtwork();

      final row = await dbService.loadRelease(release.path);
      expect(row!['art_path'], '${release.path}/cover.jpg');
    });

    test('falls back to MusicBrainz when no folder image exists', () async {
      final release = await makeRelease('Album',
          albumArtist: 'Artist', albumTitle: 'Title');
      fakeMusicBrainz.artPathToReturn = '${release.path}/cover.jpg';

      await service.retryMissingArtwork();

      final row = await dbService.loadRelease(release.path);
      expect(row!['art_path'], '${release.path}/cover.jpg');
    });

    test('skips a release that already has valid artwork', () async {
      final release = await makeRelease('Album',
          albumArtist: 'Artist', albumTitle: 'Title');
      await File('${release.path}/existing.jpg').create();
      await dbService.updateArtPath(
          release.path, '${release.path}/existing.jpg');

      await service.retryMissingArtwork();

      expect(fakeMusicBrainz.wasCalled, isFalse);
    });

    test('retries a release whose stored art_path file has been deleted',
        () async {
      final release = await makeRelease('Album',
          artPath: '${tempRoot.path}/Album/gone.jpg',
          albumArtist: 'Artist',
          albumTitle: 'Title');
      fakeMusicBrainz.artPathToReturn = '${release.path}/cover.jpg';

      await service.retryMissingArtwork();

      final row = await dbService.loadRelease(release.path);
      expect(row!['art_path'], '${release.path}/cover.jpg');
    });

    test('skips an unresolved release', () async {
      await makeRelease('Album',
          albumArtist: 'Artist', albumTitle: 'Title', scanned: false);

      await service.retryMissingArtwork();

      expect(fakeMusicBrainz.wasCalled, isFalse);
    });

    test('calls onProgress once per release attempted', () async {
      await makeRelease('Album A', albumArtist: 'A', albumTitle: 'A');
      await makeRelease('Album B', albumArtist: 'B', albumTitle: 'B');
      var calls = 0;

      await service.retryMissingArtwork(onProgress: () => calls++);

      expect(calls, 2);
    });

    test(
        'a release that fails unexpectedly does not stop later releases in '
        'the sweep', () async {
      final failing = await makeRelease('Fails',
          albumArtist: 'Artist', albumTitle: 'Title A');
      final succeeds = await makeRelease('Succeeds',
          albumArtist: 'Artist', albumTitle: 'Title B');
      fakeMusicBrainz.artPathToReturn = '${succeeds.path}/cover.jpg';
      fakeMusicBrainz.throwForFolderPaths = {failing.path};
      var progressCalls = 0;

      await service.retryMissingArtwork(onProgress: () => progressCalls++);

      final row = await dbService.loadRelease(succeeds.path);
      expect(row!['art_path'], '${succeeds.path}/cover.jpg');
      expect(progressCalls, 2);
    });

    test('calls onArtworkResolved only when something was actually found',
        () async {
      // "Found" resolves via a folder image (free); "NotFound" has neither
      // a folder image nor a MusicBrainz match (fakeMusicBrainz's default
      // artPathToReturn is null), so only one of the two should trigger
      // onArtworkResolved.
      final found =
          await makeRelease('Found', albumArtist: 'A', albumTitle: 'A');
      await File('${found.path}/cover.jpg').create();
      await makeRelease('NotFound', albumArtist: 'B', albumTitle: 'B');
      final resolvedPaths = <String>[];

      await service.retryMissingArtwork(onArtworkResolved: resolvedPaths.add);

      expect(resolvedPaths, ['${found.path}/cover.jpg']);
    });
  });

  group('loadLibrary', () {
    late DatabaseService dbService;
    late LibraryService service;

    setUp(() async {
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      service = LibraryService.forTest(dbService);
    });

    tearDown(() async {
      await dbService.closeForTest();
    });

    test('returns empty when no releases exist', () async {
      expect(await service.loadLibrary(), isEmpty);
    });

    test('returns every release, regardless of scan status', () async {
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', [
        const Track(path: '/music/a/01.mp3', title: 'Track', trackNumber: 1),
      ]);
      final releases = await service.loadLibrary();
      expect(releases.length, 1);
      expect(releases.first.name, 'Album A');
    });

    test('loads tracks in track number order', () async {
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', [
        const Track(path: '/music/a/02.mp3', title: 'B', trackNumber: 2),
        const Track(path: '/music/a/01.mp3', title: 'A', trackNumber: 1),
      ]);
      final releases = await service.loadLibrary();
      expect(releases.first.tracks.map((t) => t.trackNumber).toList(), [1, 2]);
    });

    test('populates metadataRead from the metadata_read column', () async {
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', [
        const Track(path: '/music/a/01.mp3', title: 'Unread', trackNumber: 1),
        const Track(path: '/music/a/02.mp3', title: 'Read', trackNumber: 2),
      ]);
      await dbService.markTrackMetadataRead('/music/a/02.mp3',
          title: 'Read', trackNumber: 2);

      final tracks = (await service.loadLibrary()).first.tracks;
      expect(tracks.firstWhere((t) => t.path == '/music/a/01.mp3').metadataRead,
          isFalse);
      expect(tracks.firstWhere((t) => t.path == '/music/a/02.mp3').metadataRead,
          isTrue);
    });

    test('loads tags for each release', () async {
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', []);
      await dbService.addTag('/music/a', 'jazz');
      final releases = await service.loadLibrary();
      expect(releases.first.tags, ['jazz']);
    });

    test('loads lastActivityAt from release_activity', () async {
      final t = DateTime(2025, 6, 1, 12, 0, 0);
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', []);
      await dbService.setLastActivity('/music/a', t);
      final releases = await service.loadLibrary();
      expect(releases.first.lastActivityAt, t);
    });

    test('lastActivityAt is null when no activity recorded', () async {
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', []);
      final releases = await service.loadLibrary();
      expect(releases.first.lastActivityAt, isNull);
    });

    test('artPath is null when the stored path no longer exists on disk',
        () async {
      await dbService.saveRelease('/music/a', 'Album A',
          artPath: '/does/not/exist.jpg');
      await dbService.saveTracks('/music/a', []);
      final releases = await service.loadLibrary();
      expect(releases.first.artPath, isNull);
    });
  });

  group('updateTrackMetadata', () {
    late DatabaseService dbService;
    late LibraryService service;

    setUp(() async {
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      service = LibraryService.forTest(dbService);
    });

    tearDown(() async {
      await dbService.closeForTest();
    });

    test('updates a track and marks its metadata as read', () async {
      await dbService.saveTracks('/music/a', [
        const Track(path: '/music/a/01.mp3', title: 'Old', trackNumber: 1),
      ]);
      await service.updateTrackMetadata('/music/a/01.mp3',
          title: 'New', trackNumber: 2, artist: 'Bob');
      final row = (await dbService.loadTracks('/music/a')).first;
      expect(row['title'], 'New');
      expect(row['track_number'], 2);
      expect(row['artist'], 'Bob');
      expect(row['metadata_read'], 1);
    });
  });

  group('pickLibraryFolder', () {
    late DatabaseService dbService;
    late FakeBookmarkService fakeBookmarks;
    late LibraryService service;

    setUp(() async {
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      fakeBookmarks = FakeBookmarkService();
      service = LibraryService.forTest(dbService, bookmarks: fakeBookmarks);
    });

    tearDown(() async {
      await dbService.closeForTest();
    });

    test('saves the new root and returns the path', () async {
      fakeBookmarks.pathToReturn = '/new/root';
      final path = await service.pickLibraryFolder();
      expect(path, '/new/root');
      expect(await dbService.savedLibraryRoot(), '/new/root');
    });

    test('returns null and does not save when picker is cancelled', () async {
      fakeBookmarks.pathToReturn = null;
      final path = await service.pickLibraryFolder();
      expect(path, isNull);
      expect(await dbService.savedLibraryRoot(), isNull);
    });

    test('resets library data when a different root is selected', () async {
      await dbService.saveLibraryRoot('/old/root');
      await dbService.saveRelease('/old/root/Album', 'Old Album');
      await dbService.addTag('/old/root/Album', 'jazz');

      fakeBookmarks.pathToReturn = '/new/root';
      await service.pickLibraryFolder();

      expect(await dbService.allReleasePaths(), isEmpty);
      expect(await dbService.loadRelease('/old/root/Album'), isNull);
      expect(await dbService.tagsForRelease('/old/root/Album'), isEmpty);
    });

    test('does not reset library data when the same root is re-selected',
        () async {
      await dbService.saveLibraryRoot('/music');
      await dbService.saveRelease('/music/Album', 'Album');

      fakeBookmarks.pathToReturn = '/music';
      await service.pickLibraryFolder();

      expect(await dbService.allReleasePaths(), ['/music/Album']);
    });

    test('does not reset when no previous root exists', () async {
      await dbService.saveRelease('/music/Album', 'Album');
      fakeBookmarks.pathToReturn = '/music';
      await service.pickLibraryFolder();
      // No crash, no reset (nothing to compare against)
      expect(await dbService.allReleasePaths(), ['/music/Album']);
    });
  });

  group('tag delegation', () {
    late DatabaseService dbService;
    late LibraryService service;

    setUp(() async {
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      service = LibraryService.forTest(dbService);
    });

    tearDown(() async {
      await dbService.closeForTest();
    });

    test('addTag lowercases and trims the tag', () async {
      await service.addTag('/album', '  Jazz  ');
      expect(await dbService.tagsForRelease('/album'), ['jazz']);
    });

    test('removeTag removes a tag', () async {
      await dbService.addTag('/album', 'jazz');
      await service.removeTag('/album', 'jazz');
      expect(await dbService.tagsForRelease('/album'), isEmpty);
    });

    test('allTags returns tags from the database', () async {
      await dbService.addTag('/a', 'jazz');
      await dbService.addTag('/b', 'vinyl');
      expect(await service.allTags(), containsAll(['jazz', 'vinyl']));
    });
  });
}
