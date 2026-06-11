import 'package:flutter_test/flutter_test.dart';
import 'package:surface_noise_player/models/release.dart';

void main() {
  group('Track', () {
    test('stores all fields', () {
      const track = Track(
        path: '/music/album/01 - Song.mp3',
        title: 'Song',
        trackNumber: 1,
        duration: Duration(seconds: 180),
      );
      expect(track.path, '/music/album/01 - Song.mp3');
      expect(track.title, 'Song');
      expect(track.trackNumber, 1);
      expect(track.duration, const Duration(seconds: 180));
    });

    test('duration defaults to null', () {
      const track = Track(path: '/a.mp3', title: 'A', trackNumber: 1);
      expect(track.duration, isNull);
    });
  });

  group('Release', () {
    const track1 = Track(path: '/album/01.mp3', title: 'First', trackNumber: 1);
    const track2 =
        Track(path: '/album/02.mp3', title: 'Second', trackNumber: 2);

    const release = Release(
      folderPath: '/music/album',
      name: 'My Album',
      tracks: [track1, track2],
      tags: ['jazz', 'vinyl'],
    );

    test('stores all fields', () {
      expect(release.folderPath, '/music/album');
      expect(release.name, 'My Album');
      expect(release.tracks, [track1, track2]);
      expect(release.tags, ['jazz', 'vinyl']);
    });

    test('copyWith replaces tags', () {
      final updated = release.copyWith(tags: ['electronic']);
      expect(updated.tags, ['electronic']);
      expect(updated.folderPath, release.folderPath);
      expect(updated.name, release.name);
      expect(updated.tracks, release.tracks);
    });

    test('copyWith with null preserves existing tags', () {
      final updated = release.copyWith();
      expect(updated.tags, release.tags);
    });

    test('copyWith produces a new object', () {
      final updated = release.copyWith(tags: ['rock']);
      expect(identical(updated, release), isFalse);
    });
  });
}
