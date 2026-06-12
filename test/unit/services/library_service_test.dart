import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/services/database_service.dart';
import 'package:surface_noise_player/services/library_service.dart';
import 'package:surface_noise_player/services/metadata_service.dart';
import '../../helpers/fake_metadata_service.dart';

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
      expect(LibraryService.cleanTitle('04 – En Dash Title.aiff'), 'En Dash Title');
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

  group('scanLibrary', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late FakeMetadataService fakeMetadata;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      fakeMetadata = FakeMetadataService();
      service = LibraryService.forTest(dbService, metadata: fakeMetadata);
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    Future<void> createAudioFile(Directory parent, String name) async {
      await File('${parent.path}/$name').create();
    }

    test('cleans up artwork cache at the start of each scan', () async {
      await service.scanLibrary(tempRoot.path);
      expect(fakeMetadata.cleanupCalled, isTrue);
    });

    test('populates lastActivityAt from database when present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final t = DateTime(2025, 6, 1, 12, 0, 0);
      await dbService.setLastActivity(albumDir.path, t);

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.lastActivityAt, t);
    });

    test('lastActivityAt is null when not in database', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.lastActivityAt, isNull);
    });

    test('returns empty list when root does not exist', () async {
      final releases = await service.scanLibrary('/nonexistent/path');
      expect(releases, isEmpty);
    });

    test('returns empty list when root has no subfolders', () async {
      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases, isEmpty);
    });

    test('ignores subfolders with no audio files', () async {
      await Directory('${tempRoot.path}/EmptyAlbum').create();
      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases, isEmpty);
    });

    test('scans a subfolder containing audio files as a release', () async {
      final albumDir = await Directory('${tempRoot.path}/My Album').create();
      await createAudioFile(albumDir, '01 - Track One.mp3');
      await createAudioFile(albumDir, '02 - Track Two.flac');

      final releases = await service.scanLibrary(tempRoot.path);

      expect(releases.length, 1);
      expect(releases.first.name, 'My Album');
      expect(releases.first.tracks.length, 2);
    });

    test('extracts correct track titles via cleanTitle', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01 - Hello World.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.first.title, 'Hello World');
    });

    test('numbers tracks starting from 1', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, '02.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      final trackNumbers = releases.first.tracks.map((t) => t.trackNumber).toList();
      expect(trackNumbers, [1, 2]);
    });

    test('returns all releases (order is not guaranteed)', () async {
      await Directory('${tempRoot.path}/Zebra').create()
          .then((d) => createAudioFile(d, 'a.mp3'));
      await Directory('${tempRoot.path}/Apple').create()
          .then((d) => createAudioFile(d, 'a.mp3'));

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.map((r) => r.name), containsAll(['Apple', 'Zebra']));
    });

    test('attaches saved tags to a release', () async {
      final albumDir = await Directory('${tempRoot.path}/Tagged Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await dbService.addTag(albumDir.path, 'jazz');
      await dbService.addTag(albumDir.path, 'vinyl');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tags, containsAll(['jazz', 'vinyl']));
    });

    test('ignores files directly in root (not in subfolders)', () async {
      await createAudioFile(tempRoot, 'stray.mp3');
      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases, isEmpty);
    });

    test('recognises all supported audio extensions', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      for (final ext in ['.mp3', '.flac', '.aac', '.m4a', '.wav', '.ogg', '.opus', '.aiff', '.aif']) {
        await createAudioFile(albumDir, 'track$ext');
      }
      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.length, 9);
    });

    test('ignores non-audio files', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, 'cover.jpg');
      await createAudioFile(albumDir, 'notes.txt');
      await createAudioFile(albumDir, '01.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.length, 1);
    });

    test('sets artPath to cover.jpg when present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, 'cover.jpg');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.artPath, '${albumDir.path}/cover.jpg');
    });

    test('artPath is null when no image file present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.artPath, isNull);
    });

    test('prefers cover.jpg over folder.jpg', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, 'folder.jpg');
      await createAudioFile(albumDir, 'cover.jpg');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.artPath, '${albumDir.path}/cover.jpg');
    });

    test('uses embedded artwork when no image file is present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata = FakeMetadataService(artworkPaths: {trackPath: '/tmp/extracted.jpg'});
      service = LibraryService.forTest(dbService, metadata: fakeMetadata);

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.artPath, '/tmp/extracted.jpg');
    });

    test('prefers image file over embedded artwork', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      await createAudioFile(albumDir, 'cover.jpg');
      fakeMetadata = FakeMetadataService(artworkPaths: {trackPath: '/tmp/extracted.jpg'});
      service = LibraryService.forTest(dbService, metadata: fakeMetadata);

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.artPath, '${albumDir.path}/cover.jpg');
    });

    test('falls back to folder.jpg when no preferred name matches', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, 'folder.jpg');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.artPath, '${albumDir.path}/folder.jpg');
    });

    test('uses metadata title when present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(title: 'Metadata Title');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.first.title, 'Metadata Title');
    });

    test('falls back to filename title when metadata title absent', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01 - Filename Title.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.first.title, 'Filename Title');
    });

    test('uses metadata track number when present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/track.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(trackNumber: 5);

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.first.trackNumber, 5);
    });

    test('sets track artist from metadata', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(artist: 'Track Artist');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.first.artist, 'Track Artist');
    });

    test('track artist is null when not in metadata', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.first.artist, isNull);
    });

    test('release name uses albumArtist - albumTitle from metadata', () async {
      final albumDir = await Directory('${tempRoot.path}/Some Folder').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(
        albumArtist: 'The Artist',
        albumTitle: 'Great Album',
      );

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.name, 'The Artist - Great Album');
    });

    test('release name falls back to folder name when metadata absent', () async {
      final albumDir = await Directory('${tempRoot.path}/My Folder Name').create();
      await createAudioFile(albumDir, '01.mp3');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.name, 'My Folder Name');
    });

    test('release name falls back to folder name when only one metadata field present', () async {
      final albumDir = await Directory('${tempRoot.path}/My Folder').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(albumTitle: 'Album Only');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.name, 'My Folder');
    });

    test('stores albumTitle and albumArtist on release', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(
        albumArtist: 'The Artist',
        albumTitle: 'Great Album',
      );

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.albumArtist, 'The Artist');
      expect(releases.first.albumTitle, 'Great Album');
    });
  });

  group('quickScanLibrary', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late FakeMetadataService fakeMetadata;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_quick_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      fakeMetadata = FakeMetadataService();
      service = LibraryService.forTest(dbService, metadata: fakeMetadata);
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    Future<void> createAudioFile(Directory parent, String name) async {
      await File('${parent.path}/$name').create();
    }

    test('returns empty list when root does not exist', () async {
      final releases = await service.quickScanLibrary('/nonexistent', []);
      expect(releases, isEmpty);
    });

    test('adds a new folder not in the existing list', () async {
      final albumDir = await Directory('${tempRoot.path}/New Album').create();
      await createAudioFile(albumDir, '01.mp3');

      final releases = await service.quickScanLibrary(tempRoot.path, []);
      expect(releases.length, 1);
      expect(releases.first.name, 'New Album');
    });

    test('keeps an existing release whose folder still exists', () async {
      final albumDir = await Directory('${tempRoot.path}/Existing Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final existing = [
        Release(folderPath: albumDir.path, name: 'Existing Album', tracks: const [], tags: const []),
      ];

      final releases = await service.quickScanLibrary(tempRoot.path, existing);
      expect(releases.length, 1);
      expect(releases.first.name, 'Existing Album');
    });

    test('does not re-scan an existing release', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      fakeMetadata.responses['${albumDir.path}/01.mp3'] = const AudioMetadata(title: 'Should Not Appear');
      final existing = [
        Release(folderPath: albumDir.path, name: 'Album', tracks: const [], tags: const []),
      ];

      final releases = await service.quickScanLibrary(tempRoot.path, existing);
      // Tracks come from existing (empty), not re-scanned
      expect(releases.first.tracks, isEmpty);
    });

    test('removes a release whose folder no longer exists', () async {
      final existing = [
        Release(folderPath: '${tempRoot.path}/Gone Album', name: 'Gone Album', tracks: const [], tags: const []),
      ];

      final releases = await service.quickScanLibrary(tempRoot.path, existing);
      expect(releases, isEmpty);
    });

    test('handles a mix of new, existing, and removed folders', () async {
      final keepDir = await Directory('${tempRoot.path}/Keep').create();
      await createAudioFile(keepDir, '01.mp3');
      final newDir = await Directory('${tempRoot.path}/New').create();
      await createAudioFile(newDir, '01.mp3');

      final existing = [
        Release(folderPath: keepDir.path, name: 'Keep', tracks: const [], tags: const []),
        Release(folderPath: '${tempRoot.path}/Gone', name: 'Gone', tracks: const [], tags: const []),
      ];

      final releases = await service.quickScanLibrary(tempRoot.path, existing);
      expect(releases.length, 2);
      expect(releases.map((r) => r.name), containsAll(['Keep', 'New']));
      expect(releases.map((r) => r.name), isNot(contains('Gone')));
    });

    test('returns all expected releases (order is not guaranteed)', () async {
      final zDir = await Directory('${tempRoot.path}/Zebra').create();
      await createAudioFile(zDir, '01.mp3');
      final aDir = await Directory('${tempRoot.path}/Apple').create();
      await createAudioFile(aDir, '01.mp3');

      final releases = await service.quickScanLibrary(tempRoot.path, []);
      expect(releases.map((r) => r.name), containsAll(['Zebra', 'Apple']));
    });

    test('sets lastActivityAt on newly discovered folders', () async {
      final albumDir = await Directory('${tempRoot.path}/New Album').create();
      await createAudioFile(albumDir, '01.mp3');

      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final releases = await service.quickScanLibrary(tempRoot.path, []);
      expect(releases.first.lastActivityAt, isNotNull);
      expect(releases.first.lastActivityAt!.isAfter(before), isTrue);
    });

    test('persists lastActivityAt to database for new folders', () async {
      final albumDir = await Directory('${tempRoot.path}/New Album').create();
      await createAudioFile(albumDir, '01.mp3');

      await service.quickScanLibrary(tempRoot.path, []);
      final activities = await dbService.allLastActivities();
      expect(activities[albumDir.path], isNotNull);
    });

    test('does not clean up artwork cache', () async {
      await service.quickScanLibrary(tempRoot.path, []);
      expect(fakeMetadata.cleanupCalled, isFalse);
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
