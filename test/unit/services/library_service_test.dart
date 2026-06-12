import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:surface_noise_player/services/database_service.dart';
import 'package:surface_noise_player/services/library_service.dart';

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
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      service = LibraryService.forTest(dbService);
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    Future<void> createAudioFile(Directory parent, String name) async {
      await File('${parent.path}/$name').create();
    }

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

    test('sorts releases alphabetically by name', () async {
      await Directory('${tempRoot.path}/Zebra').create()
          .then((d) => createAudioFile(d, 'a.mp3'));
      await Directory('${tempRoot.path}/Apple').create()
          .then((d) => createAudioFile(d, 'a.mp3'));
      await Directory('${tempRoot.path}/Mango').create()
          .then((d) => createAudioFile(d, 'a.mp3'));

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.map((r) => r.name).toList(), ['Apple', 'Mango', 'Zebra']);
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
      for (final ext in ['.mp3', '.flac', '.aac', '.m4a', '.wav', '.ogg', '.opus', '.aiff']) {
        await createAudioFile(albumDir, 'track$ext');
      }
      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.tracks.length, 8);
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

    test('falls back to folder.jpg when no preferred name matches', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, 'folder.jpg');

      final releases = await service.scanLibrary(tempRoot.path);
      expect(releases.first.artPath, '${albumDir.path}/folder.jpg');
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
