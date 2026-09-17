class Track {
  final String path;
  final String title;
  final int trackNumber;
  final Duration? duration;
  final String? artist;
  // Has real (file-tag) metadata replaced the filename-derived guess yet?
  final bool metadataRead;

  const Track({
    required this.path,
    required this.title,
    required this.trackNumber,
    this.duration,
    this.artist,
    this.metadataRead = false,
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
  final DateTime? lastActivityAt;
  final bool isAvailable;

  const Release({
    required this.folderPath,
    required this.name,
    required this.tracks,
    required this.tags,
    this.artPath,
    this.albumTitle,
    this.albumArtist,
    this.lastActivityAt,
    this.isAvailable = true,
  });

  Release copyWith(
          {List<String>? tags, DateTime? lastActivityAt, bool? isAvailable}) =>
      Release(
        folderPath: folderPath,
        name: name,
        tracks: tracks,
        tags: tags ?? this.tags,
        artPath: artPath,
        albumTitle: albumTitle,
        albumArtist: albumArtist,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        isAvailable: isAvailable ?? this.isAvailable,
      );
}
