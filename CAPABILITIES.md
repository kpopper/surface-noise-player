# Surface Noise Player — Capabilities

This file defines what the app is supposed to do, in plain language.
Each statement is covered by at least one test. Add a statement here before
writing a feature; remove or update it when behaviour changes.

---

## Library scanning

- Each direct subfolder of the selected root that contains at least one audio file is treated as a release
- Files directly in the root (not in a subfolder) are ignored
- A subfolder with no audio files is ignored
- Recognised audio formats: `.mp3` `.flac` `.aac` `.m4a` `.wav` `.ogg` `.opus` `.aiff` `.aif`
- Non-audio files inside a release folder (e.g. cover art, text files) are ignored
- Releases are sorted alphabetically by name, case-insensitive
- Tracks within a release are numbered starting from 1
- Leading track-number prefixes are stripped from filenames to produce the track title (e.g. `01 - Song.mp3` → `Song`, `02. Another.flac` → `Another`)
- A previously selected root folder is remembered across app restarts

## Tags

- A tag is stored in lowercase with surrounding whitespace trimmed
- Adding the same tag to a release twice has no effect
- Removing a tag that does not exist is a no-op
- A release can have multiple tags
- Tags are scoped to a release — adding a tag to one release does not affect another
- Tags persist across app restarts
- The full list of distinct tags across all releases is available, sorted alphabetically

## Tag filtering

- When no filter is active, all releases are shown
- Activating a tag filter shows only releases that have that tag
- Multiple active filters are combined with AND logic — a release must have all active tags to appear
- Clearing the filter restores the full release list
- A filter that matches no releases shows an empty state

## Album art

- A release folder may contain cover art as a `.jpg`, `.jpeg`, or `.png` file
- Preferred filenames are checked in order: `cover.jpg`, `folder.jpg`, `artwork.jpg`, `front.jpg`
- If none of those are present, the first image file found in the folder is used
- If no image file is present, embedded artwork from the audio files is extracted and used
- If neither a file nor embedded artwork is available, `artPath` is null and a placeholder is shown
- A release card shows a square thumbnail of the cover art (or placeholder) on the left
- The release screen shows the cover art as a full-width header above the track list
- The mini player shows a small thumbnail next to the track and album name

## Audio metadata

- Track title, track number, and track artist are read from each file's embedded metadata tags (ID3, FLAC, M4A, etc.)
- If a file has no metadata, track title falls back to filename parsing and track number falls back to alphabetical file order
- Album title and album artist are read from the first track's metadata
- When both album artist and album title are present, the release name is displayed as "{albumArtist} - {albumTitle}"
- When metadata is absent, the release name falls back to the folder name
- Track artist is shown alongside the track title in the release screen track list
- Album artwork is shown on the lock screen and in the Now Playing controls

## Release data

- A release has a folder path, a name, a list of tracks, a list of tags, an optional art path, an optional album title, and an optional album artist
- Copying a release with new tags preserves all other fields
- A track has a file path, a title, a track number, an optional duration, and an optional artist

## Library screen

- When no folder has been selected, an empty-state prompt is shown
- When a folder is selected and contains no audio subfolders, a "no releases found" message is shown
- When a folder is selected and releases exist, one card is shown per release
- When an active tag filter has no matching releases, a "no releases match" message is shown

## Release card

- A release card displays the release name
- When a release has no tags, the card shows the track count
- When a release has tags, the card shows the tags instead of the track count
- Tapping a release card opens that release
