import 'package:audio_service/audio_service.dart';
import '../services/abstract_player_service.dart';

typedef NowPlayingDetails = ({String title, String? artist, String? album});

// What to show for the current track, or null when nothing is playing or
// requested. The loaded MediaItem tag reflects what just_audio actually has
// queued; svc.currentTrack is set as soon as playback is requested, even
// before a download-wait completes and a source is loaded — so fall back to
// it to show something immediately. A non-null tag can also still be the
// *previous* track's while the newly requested one downloads, so it's only
// trusted once it actually matches what was requested.
NowPlayingDetails? resolveNowPlayingDetails(
    AbstractPlayerService svc, MediaItem? tag) {
  final pendingTrack = svc.currentTrack;
  if (tag == null && pendingTrack == null) return null;
  final tagIsCurrent =
      tag != null && (pendingTrack == null || tag.id == pendingTrack.path);
  if (tagIsCurrent) {
    return (title: tag.title, artist: tag.artist, album: tag.album);
  }
  final release = svc.currentRelease;
  return (
    title: pendingTrack!.title,
    artist: pendingTrack.artist ?? release?.albumArtist,
    album: release?.albumTitle ?? release?.name,
  );
}
