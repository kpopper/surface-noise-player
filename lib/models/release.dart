class Track {
  final String path;
  final String title;
  final int trackNumber;
  final Duration? duration;
  final String? artist;

  const Track({
    required this.path,
    required this.title,
    required this.trackNumber,
    this.duration,
    this.artist,
  });
}

class Release {
  final String folderPath;
  final String name;
  final List<Track> tracks;
  final List<String> tags;
  final String? artPath;
  final String? albumTitle;
  final String? albumArtist;

  const Release({
    required this.folderPath,
    required this.name,
    required this.tracks,
    required this.tags,
    this.artPath,
    this.albumTitle,
    this.albumArtist,
  });

  Release copyWith({List<String>? tags}) => Release(
        folderPath: folderPath,
        name: name,
        tracks: tracks,
        tags: tags ?? this.tags,
        artPath: artPath,
        albumTitle: albumTitle,
        albumArtist: albumArtist,
      );
}
