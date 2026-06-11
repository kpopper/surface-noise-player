class Track {
  final String path;
  final String title;
  final int trackNumber;
  final Duration? duration;

  const Track({
    required this.path,
    required this.title,
    required this.trackNumber,
    this.duration,
  });
}

class Release {
  final String folderPath;
  final String name;
  final List<Track> tracks;
  final List<String> tags;

  const Release({
    required this.folderPath,
    required this.name,
    required this.tracks,
    required this.tags,
  });

  Release copyWith({List<String>? tags}) => Release(
        folderPath: folderPath,
        name: name,
        tracks: tracks,
        tags: tags ?? this.tags,
      );
}
