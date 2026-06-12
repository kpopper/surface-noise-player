import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/release.dart';
import 'abstract_player_service.dart';

class PlayerService implements AbstractPlayerService {
  static PlayerService? _instance;
  PlayerService._();
  static PlayerService get instance => _instance ??= PlayerService._();

  final AudioPlayer player = AudioPlayer();

  @override
  Release? currentRelease;

  @override
  Stream<SequenceState?> get sequenceStateStream => player.sequenceStateStream;
  @override
  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  @override
  Stream<Duration> get positionStream => player.positionStream;
  @override
  Stream<Duration?> get durationStream => player.durationStream;
  @override
  bool get hasPrevious => player.hasPrevious;
  @override
  bool get hasNext => player.hasNext;
  @override
  Future<void> seekToPrevious() => player.seekToPrevious();
  @override
  Future<void> seekToNext() => player.seekToNext();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> playRelease(Release release, {int trackIndex = 0}) async {
    currentRelease = release;
    final sources = release.tracks.map((t) => AudioSource.uri(
      Uri.file(t.path),
      tag: MediaItem(
        id: t.path,
        title: t.title,
        artist: t.artist ?? release.albumArtist,
        album: release.albumTitle ?? release.name,
        artUri: release.artPath != null ? Uri.file(release.artPath!) : null,
      ),
    )).toList();
    await player.setAudioSources(sources, initialIndex: trackIndex);
    await player.play();
  }

  @override
  Future<void> playTrack(Release release, int trackIndex) =>
      playRelease(release, trackIndex: trackIndex);

  void dispose() {
    player.dispose();
  }
}
