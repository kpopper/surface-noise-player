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
- Tracks within a release are ordered by track number
- Track numbers are read from embedded metadata; if absent, tracks are numbered in alphabetical filename order starting from 1
- Leading track-number prefixes are stripped from filenames to produce the track title (e.g. `01 - Song.mp3` → `Song`, `02. Another.flac` → `Another`)
- A previously selected root folder is remembered across app restarts
- On app launch, selected releases are loaded from the database without re-scanning the file system and without requesting any iCloud downloads — tracks download on demand when playback is requested (see Playback)
- When a release folder is selected in the management screen, a full scan runs for that folder: metadata is extracted, artwork is resolved, and the result is persisted to the database
- A newly selected folder is assigned an activity timestamp; a folder that was previously selected retains its existing timestamp

## Library management

- The library screen shows only selected releases, not all subfolders of the root
- A management screen lists every direct subfolder of the root as a checkbox list, sorted alphabetically
- The management screen has a search field that filters the folder list to names containing the search text (case-insensitive); clearing the search restores the full list
- In the management screen, the search field loses focus (closing the keyboard) when the folder list below it is scrolled or tapped
- In the management screen, a folder currently selected (in the library) is shown in bold; unselected folders are shown in normal weight, so selected albums stand out from new/unselected ones
- Selecting a different folder resets the database
- Selecting a folder scans it, persists the release to the database, triggers an iCloud download of its audio files, and immediately shows it in the library
- Deselecting a folder removes it from the selected releases, evicts its audio files from iCloud storage, and removes it from the library
- Tags and play history are preserved when a folder is deselected — they remain in the database keyed by folder path
- Selected releases persist across app restarts

## Library sorting

- Releases are sorted by most recent activity (played or added), newest first
- A release's activity timestamp is set when it is first discovered and updated when it is played
- Releases with no recorded activity are sorted alphabetically at the end of the list

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
- If neither a file nor embedded artwork is available, and the release has an album title and at least one of album artist or track artist in its metadata, cover art is fetched automatically from MusicBrainz Cover Art Archive; the earliest release date is preferred to identify the release group, and artwork is fetched at the release-group level so that any edition's scanned cover satisfies the lookup even if the earliest-dated edition itself has none; the image is saved as `cover.jpg` in the release folder
- If both artist and album title metadata are absent, the MusicBrainz lookup is skipped
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

## Playback

- Tracks are loaded and played one at a time, in release track order, regardless of local availability at the moment playback starts — the full track list is the queue, not just the currently-available subset
- Before loading a track, its local availability is checked; if it is not locally available, an iCloud download is requested for it and playback pauses (showing a buffering/waiting state) until it becomes available, then playback starts automatically without further user action
- The mini player (and the Now Playing screen, if open) appears as soon as a track is requested, not only once it is actually loaded into the player — tapping a track that needs to download gives immediate visual feedback rather than appearing to do nothing until the download finishes
- While the player is waiting for a track to download, a spinner is shown over the album artwork in both the mini player and the Now Playing screen, and over the currently-selected track's row in the release screen
- While one track plays, a download is proactively requested for the next track in the queue, so it is more likely to already be available by the time it's needed
- If a requested download does not complete within a timeout, a message is shown and playback automatically advances to the next track, as if the track had failed to play
- If a track that exists on disk still fails to play (e.g. a corrupt file), a message is shown and playback automatically advances to the next track
- Manually skipping to the next or previous track applies the same download-wait-then-play behaviour as natural advancement
- A cancelled/superseded playback request (e.g. tapping a second track, or skipping, before the previous one finishes loading or downloading) does not show an error message and does not leave a stale buffering spinner showing
- Skip previous/next moves through the release's track order, not through play history, so skipping back from a track works even if the earlier track was never played this session
- If no track in the release is available and none can be downloaded, a message is shown and playback stops cleanly without looping or crashing
- Reaching the end of the release's last track stops playback and closes the mini player, rather than leaving it showing the last track as playing
- If playback stops because no further track could be played, the mini player closes the same way

## Mini player

- Visible at the bottom of every screen whenever something is playing
- Shows current track title, album, and art thumbnail
- Provides play/pause and skip controls
- Tapping it opens the Now Playing screen
- Sized for easy tapping: larger art thumbnail, text, and control icons than a standard compact bar, with generous padding

## Now Playing screen

- Opens full-screen from the mini player
- Shows full-size album art, release name, track title, and artist
- Progress bar showing current position, scrubbable to seek
- Play/pause, previous, and next controls
- Dismissed by tapping the close button or swiping down
- Automatically closes itself if playback stops (e.g. the queue finishes or runs out of playable tracks) while it's open

## Library screen

- When no root folder has been selected, an empty-state "Set up Library" prompt is shown
- When a root folder is selected but no albums are selected, a "No albums selected" message is shown with a button to open the management screen
- When releases exist, one card is shown per release
- When an active tag filter has no matching releases, a "no releases match" message is shown
- The app bar has a manage button that opens the library management screen
- The app bar has a refresh button; tapping it re-scans every selected release folder on disk, updating tracks, metadata, and artwork; activity timestamps are not changed
- A release marked unavailable is shown in the list but cannot be tapped to open

## Release screen

- Each track's local availability (e.g. downloaded from iCloud or not) is checked when the screen opens
- A track not currently available locally shows a small cloud icon instead of its track number, but can still be tapped to play — tapping it triggers the download-wait-then-play behaviour described under Playback

## Release card

- A release card displays the release name
- When a release has no tags, the card shows the track count
- When a release has tags, the card shows the tags instead of the track count, as plain text (no pill/chip border)
- Tags shown in the release card use the same font size as the track count
- Tapping a release card opens that release

## Tag colours

- Each distinct tag is consistently assigned a colour from a fixed palette, derived from the tag string
- In the release card, each tag is rendered in its assigned colour as plain text
- In the filter bar, unselected filter chips show the tag label in its assigned colour with a default background; selected chips show a solid background in the tag's colour with white text
- In the release screen, deletable tag chips use the tag's assigned colour as a tinted background with the label in that colour
