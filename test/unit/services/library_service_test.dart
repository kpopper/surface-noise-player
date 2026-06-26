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

  group('selectRelease', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late FakeMetadataService fakeMetadata;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_select_test_');
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

    test('returns null when folder has no audio files', () async {
      final emptyDir = await Directory('${tempRoot.path}/Empty').create();
      final result = await service.selectRelease(emptyDir.path);
      expect(result, isNull);
    });

    test('returns a release with tracks when folder has audio files', () async {
      final albumDir = await Directory('${tempRoot.path}/My Album').create();
      await createAudioFile(albumDir, '01 - Track One.mp3');
      await createAudioFile(albumDir, '02 - Track Two.flac');

      final release = await service.selectRelease(albumDir.path);

      expect(release, isNotNull);
      expect(release!.name, 'My Album');
      expect(release.tracks.length, 2);
    });

    test('recognises all supported audio extensions', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      for (final ext in ['.mp3', '.flac', '.aac', '.m4a', '.wav', '.ogg', '.opus', '.aiff', '.aif']) {
        await createAudioFile(albumDir, 'track$ext');
      }
      final release = await service.selectRelease(albumDir.path);
      expect(release!.tracks.length, 9);
    });

    test('ignores non-audio files', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, 'cover.jpg');
      await createAudioFile(albumDir, 'notes.txt');
      await createAudioFile(albumDir, '01.mp3');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.tracks.length, 1);
    });

    test('extracts correct track titles via cleanTitle', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01 - Hello World.mp3');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.tracks.first.title, 'Hello World');
    });

    test('orders tracks by track number', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '02.mp3');
      await createAudioFile(albumDir, '01.mp3');

      final release = await service.selectRelease(albumDir.path);
      final trackNumbers = release!.tracks.map((t) => t.trackNumber).toList();
      expect(trackNumbers, [1, 2]);
    });

    test('sets artPath to cover.jpg when present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, 'cover.jpg');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.artPath, '${albumDir.path}/cover.jpg');
    });

    test('artPath is null when no image file present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.artPath, isNull);
    });

    test('prefers cover.jpg over folder.jpg', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, 'folder.jpg');
      await createAudioFile(albumDir, 'cover.jpg');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.artPath, '${albumDir.path}/cover.jpg');
    });

    test('uses embedded artwork when no image file is present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata = FakeMetadataService(artworkPaths: {trackPath: '/tmp/extracted.jpg'});
      service = LibraryService.forTest(dbService, metadata: fakeMetadata);

      final release = await service.selectRelease(albumDir.path);
      expect(release!.artPath, '/tmp/extracted.jpg');
    });

    test('prefers image file over embedded artwork', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      await createAudioFile(albumDir, 'cover.jpg');
      fakeMetadata = FakeMetadataService(artworkPaths: {trackPath: '/tmp/extracted.jpg'});
      service = LibraryService.forTest(dbService, metadata: fakeMetadata);

      final release = await service.selectRelease(albumDir.path);
      expect(release!.artPath, '${albumDir.path}/cover.jpg');
    });

    test('uses metadata title when present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(title: 'Metadata Title');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.tracks.first.title, 'Metadata Title');
    });

    test('uses metadata track number when present', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/track.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(trackNumber: 5);

      final release = await service.selectRelease(albumDir.path);
      expect(release!.tracks.first.trackNumber, 5);
    });

    test('sets track artist from metadata', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(artist: 'Track Artist');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.tracks.first.artist, 'Track Artist');
    });

    test('track artist is null when not in metadata', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.tracks.first.artist, isNull);
    });

    test('release name uses albumArtist - albumTitle from metadata', () async {
      final albumDir = await Directory('${tempRoot.path}/Some Folder').create();
      final trackPath = '${albumDir.path}/01.mp3';
      await File(trackPath).create();
      fakeMetadata.responses[trackPath] = const AudioMetadata(
        albumArtist: 'The Artist',
        albumTitle: 'Great Album',
      );

      final release = await service.selectRelease(albumDir.path);
      expect(release!.name, 'The Artist - Great Album');
    });

    test('release name falls back to folder name when metadata absent', () async {
      final albumDir = await Directory('${tempRoot.path}/My Folder Name').create();
      await createAudioFile(albumDir, '01.mp3');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.name, 'My Folder Name');
    });

    test('attaches saved tags to the release', () async {
      final albumDir = await Directory('${tempRoot.path}/Tagged Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await dbService.addTag(albumDir.path, 'jazz');
      await dbService.addTag(albumDir.path, 'vinyl');

      final release = await service.selectRelease(albumDir.path);
      expect(release!.tags, containsAll(['jazz', 'vinyl']));
    });

    test('assigns a new activity timestamp when folder has no prior activity', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final before = DateTime.now().subtract(const Duration(seconds: 1));

      final release = await service.selectRelease(albumDir.path);

      expect(release!.lastActivityAt, isNotNull);
      expect(release.lastActivityAt!.isAfter(before), isTrue);
    });

    test('updates activity timestamp on re-selection so the release sorts to top', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final old = DateTime(2025, 1, 1, 12, 0, 0);
      await dbService.setLastActivity(albumDir.path, old);

      final before = DateTime.now();
      final release = await service.selectRelease(albumDir.path);
      expect(release!.lastActivityAt, isNotNull);
      expect(release.lastActivityAt!.isAfter(old), isTrue);
      expect(release.lastActivityAt!.isAfter(before) || release.lastActivityAt!.isAtSameMomentAs(before), isTrue);
    });

    test('persists release to database', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      await service.selectRelease(albumDir.path);

      final row = await dbService.loadRelease(albumDir.path);
      expect(row, isNotNull);
      expect(row!['name'], 'Album');
    });

    test('persists tracks to database', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await createAudioFile(albumDir, '02.mp3');

      await service.selectRelease(albumDir.path);

      final tracks = await dbService.loadTracks(albumDir.path);
      expect(tracks.length, 2);
    });

    test('adds folder to selected_releases', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      await service.selectRelease(albumDir.path);

      expect(await dbService.allSelectedPaths(), contains(albumDir.path));
    });
  });

  group('MusicBrainz artwork fallback', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late FakeMetadataService fakeMetadata;
    late FakeMusicBrainzService fakeMusicBrainz;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_mb_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      fakeMetadata = FakeMetadataService();
      fakeMusicBrainz = FakeMusicBrainzService();
      service = LibraryService.forTest(dbService,
          metadata: fakeMetadata, musicBrainz: fakeMusicBrainz);
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    Future<void> createAudioFile(Directory parent, String name) async {
      await File('${parent.path}/$name').create();
    }

    test('selectRelease fetches from MusicBrainz when no local art is found', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final trackPath = '${albumDir.path}/01.mp3';
      fakeMetadata.responses[trackPath] =
          const AudioMetadata(albumArtist: 'Artist', albumTitle: 'Album');
      fakeMusicBrainz.artPathToReturn = '${albumDir.path}/cover.jpg';

      final release = await service.selectRelease(albumDir.path);

      expect(release!.artPath, '${albumDir.path}/cover.jpg');
      expect(fakeMusicBrainz.wasCalled, isTrue);
      expect(fakeMusicBrainz.lastFetchedArtist, 'Artist');
      expect(fakeMusicBrainz.lastFetchedTitle, 'Album');
    });

    test('selectRelease does not fetch from MusicBrainz when local art is found', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await File('${albumDir.path}/cover.jpg').create();
      fakeMusicBrainz.artPathToReturn = '/some/other/path.jpg';

      final release = await service.selectRelease(albumDir.path);

      expect(release!.artPath, '${albumDir.path}/cover.jpg');
      expect(fakeMusicBrainz.wasCalled, isFalse);
    });

    test('rescanRelease fetches from MusicBrainz when no local art is found', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final trackPath = '${albumDir.path}/01.mp3';
      fakeMetadata.responses[trackPath] =
          const AudioMetadata(albumArtist: 'Artist', albumTitle: 'Album');
      fakeMusicBrainz.artPathToReturn = '${albumDir.path}/cover.jpg';
      await service.selectRelease(albumDir.path);

      fakeMusicBrainz.wasCalled = false;
      await service.rescanRelease(albumDir.path);

      final row = await dbService.loadRelease(albumDir.path);
      expect(row!['art_path'], '${albumDir.path}/cover.jpg');
      expect(fakeMusicBrainz.wasCalled, isTrue);
    });

    test('rescanRelease does not fetch from MusicBrainz when local art is found', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await File('${albumDir.path}/cover.jpg').create();
      await service.selectRelease(albumDir.path);

      fakeMusicBrainz.wasCalled = false;
      await service.rescanRelease(albumDir.path);

      expect(fakeMusicBrainz.wasCalled, isFalse);
    });

    test('selectRelease uses track artist as fallback when albumArtist is absent', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final trackPath = '${albumDir.path}/01.mp3';
      fakeMetadata.responses[trackPath] =
          const AudioMetadata(artist: 'Electrelane', albumTitle: 'The Power Out');
      fakeMusicBrainz.artPathToReturn = '${albumDir.path}/cover.jpg';

      final release = await service.selectRelease(albumDir.path);

      expect(release!.artPath, '${albumDir.path}/cover.jpg');
      expect(fakeMusicBrainz.wasCalled, isTrue);
      expect(fakeMusicBrainz.lastFetchedArtist, 'Electrelane');
      expect(fakeMusicBrainz.lastFetchedTitle, 'The Power Out');
    });

    test('selectRelease skips MusicBrainz when both artist and album title are absent', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');

      await service.selectRelease(albumDir.path);

      expect(fakeMusicBrainz.wasCalled, isFalse);
    });
  });

  group('rescanRelease', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late FakeMetadataService fakeMetadata;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_rescan_test_');
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

    test('updates tracks in the database', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await service.selectRelease(albumDir.path);

      await createAudioFile(albumDir, '02.mp3');
      await service.rescanRelease(albumDir.path);

      final tracks = await dbService.loadTracks(albumDir.path);
      expect(tracks.length, 2);
    });

    test('updates artwork in the database', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      await service.selectRelease(albumDir.path);
      expect((await dbService.loadRelease(albumDir.path))!['art_path'], isNull);

      await File('${albumDir.path}/cover.jpg').create();
      await service.rescanRelease(albumDir.path);

      final row = await dbService.loadRelease(albumDir.path);
      expect(row!['art_path'], '${albumDir.path}/cover.jpg');
    });

    test('preserves lastActivityAt', () async {
      final albumDir = await Directory('${tempRoot.path}/Album').create();
      await createAudioFile(albumDir, '01.mp3');
      final t = DateTime(2025, 3, 15, 12, 0, 0);
      await dbService.setLastActivity(albumDir.path, t);
      await service.selectRelease(albumDir.path);
      await dbService.setLastActivity(albumDir.path, t);

      await service.rescanRelease(albumDir.path);

      final activities = await dbService.allLastActivities();
      expect(activities[albumDir.path], t);
    });

    test('does nothing when folder has no audio files', () async {
      final albumDir = await Directory('${tempRoot.path}/Empty').create();
      await service.rescanRelease(albumDir.path);
      expect(await dbService.loadRelease(albumDir.path), isNull);
    });
  });

  group('loadSelectedReleases', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_load_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      service = LibraryService.forTest(dbService);
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    test('returns empty when no releases selected', () async {
      expect(await service.loadSelectedReleases(), isEmpty);
    });

    test('returns releases matching selected paths', () async {
      await dbService.addSelectedRelease('/music/a');
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', [
        const Track(path: '/music/a/01.mp3', title: 'Track', trackNumber: 1),
      ]);

      final releases = await service.loadSelectedReleases();
      expect(releases.length, 1);
      expect(releases.first.name, 'Album A');
    });

    test('skips selected paths with no matching release row', () async {
      await dbService.addSelectedRelease('/music/orphan');

      final releases = await service.loadSelectedReleases();
      expect(releases, isEmpty);
    });

    test('loads tracks in track number order', () async {
      await dbService.addSelectedRelease('/music/a');
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', [
        const Track(path: '/music/a/02.mp3', title: 'B', trackNumber: 2),
        const Track(path: '/music/a/01.mp3', title: 'A', trackNumber: 1),
      ]);

      final releases = await service.loadSelectedReleases();
      expect(releases.first.tracks.map((t) => t.trackNumber).toList(), [1, 2]);
    });

    test('loads tags for each release', () async {
      await dbService.addSelectedRelease('/music/a');
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', []);
      await dbService.addTag('/music/a', 'jazz');

      final releases = await service.loadSelectedReleases();
      expect(releases.first.tags, ['jazz']);
    });

    test('loads lastActivityAt from release_activity', () async {
      final t = DateTime(2025, 6, 1, 12, 0, 0);
      await dbService.addSelectedRelease('/music/a');
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', []);
      await dbService.setLastActivity('/music/a', t);

      final releases = await service.loadSelectedReleases();
      expect(releases.first.lastActivityAt, t);
    });

    test('lastActivityAt is null when no activity recorded', () async {
      await dbService.addSelectedRelease('/music/a');
      await dbService.saveRelease('/music/a', 'Album A');
      await dbService.saveTracks('/music/a', []);

      final releases = await service.loadSelectedReleases();
      expect(releases.first.lastActivityAt, isNull);
    });
  });

  group('deselectRelease', () {
    late DatabaseService dbService;
    late LibraryService service;

    setUp(() async {
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      service = LibraryService.forTest(dbService);
    });

    tearDown(() async {
      await dbService.closeForTest();
    });

    test('removes from selected_releases', () async {
      await dbService.addSelectedRelease('/music/a');
      await service.deselectRelease('/music/a');
      expect(await dbService.allSelectedPaths(), isEmpty);
    });

    test('removes release and tracks from database', () async {
      await dbService.saveRelease('/music/a', 'Album');
      await dbService.saveTracks('/music/a', [
        const Track(path: '/music/a/01.mp3', title: 'Track', trackNumber: 1),
      ]);
      await service.deselectRelease('/music/a');
      expect(await dbService.loadRelease('/music/a'), isNull);
      expect(await dbService.loadTracks('/music/a'), isEmpty);
    });

    test('preserves tags after deselection', () async {
      await dbService.addTag('/music/a', 'jazz');
      await service.deselectRelease('/music/a');
      expect(await dbService.tagsForRelease('/music/a'), ['jazz']);
    });

    test('preserves activity after deselection', () async {
      final t = DateTime(2025, 1, 1);
      await dbService.setLastActivity('/music/a', t);
      await service.deselectRelease('/music/a');
      final activities = await dbService.allLastActivities();
      expect(activities['/music/a'], t);
    });
  });

  group('listAllFolders', () {
    late Directory tempRoot;
    late DatabaseService dbService;
    late LibraryService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('snp_list_test_');
      dbService = DatabaseService.forTest(inMemoryDatabasePath);
      service = LibraryService.forTest(dbService);
    });

    tearDown(() async {
      await dbService.closeForTest();
      await tempRoot.delete(recursive: true);
    });

    test('returns empty when root does not exist', () async {
      expect(await service.listAllFolders('/nonexistent/path'), isEmpty);
    });

    test('returns empty when root has no subfolders', () async {
      expect(await service.listAllFolders(tempRoot.path), isEmpty);
    });

    test('lists subfolders sorted alphabetically', () async {
      await Directory('${tempRoot.path}/Zebra').create();
      await Directory('${tempRoot.path}/Apple').create();
      await Directory('${tempRoot.path}/Mango').create();

      final folders = await service.listAllFolders(tempRoot.path);
      expect(folders.map((f) => f.name).toList(), ['Apple', 'Mango', 'Zebra']);
    });

    test('marks selected folders correctly', () async {
      final selected = await Directory('${tempRoot.path}/Selected').create();
      await Directory('${tempRoot.path}/Unselected').create();
      await dbService.addSelectedRelease(selected.path);

      final folders = await service.listAllFolders(tempRoot.path);
      final selectedFolder = folders.firstWhere((f) => f.name == 'Selected');
      final unselectedFolder = folders.firstWhere((f) => f.name == 'Unselected');

      expect(selectedFolder.isSelected, isTrue);
      expect(unselectedFolder.isSelected, isFalse);
    });

    test('does not include files, only directories', () async {
      await File('${tempRoot.path}/stray.mp3').create();
      await Directory('${tempRoot.path}/Album').create();

      final folders = await service.listAllFolders(tempRoot.path);
      expect(folders.length, 1);
      expect(folders.first.name, 'Album');
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
      await dbService.addSelectedRelease('/old/root/Album');
      await dbService.saveRelease('/old/root/Album', 'Old Album');
      await dbService.addTag('/old/root/Album', 'jazz');

      fakeBookmarks.pathToReturn = '/new/root';
      await service.pickLibraryFolder();

      expect(await dbService.allSelectedPaths(), isEmpty);
      expect(await dbService.loadRelease('/old/root/Album'), isNull);
      expect(await dbService.tagsForRelease('/old/root/Album'), isEmpty);
    });

    test('does not reset library data when the same root is re-selected', () async {
      await dbService.saveLibraryRoot('/music');
      await dbService.addSelectedRelease('/music/Album');
      await dbService.saveRelease('/music/Album', 'Album');

      fakeBookmarks.pathToReturn = '/music';
      await service.pickLibraryFolder();

      expect(await dbService.allSelectedPaths(), ['/music/Album']);
    });

    test('does not reset when no previous root exists', () async {
      await dbService.addSelectedRelease('/music/Album');
      fakeBookmarks.pathToReturn = '/music';
      await service.pickLibraryFolder();
      // No crash, no reset (nothing to compare against)
      expect(await dbService.allSelectedPaths(), ['/music/Album']);
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
