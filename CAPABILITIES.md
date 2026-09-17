# Surface Noise Player — Capabilities

This file defines what the app is supposed to do, in plain language.
Each statement is covered by at least one test. Add a statement here before
writing a feature; remove or update it when behaviour changes.

---

## Library scanning

- The library is every direct subfolder of the selected root that contains at least one audio file — there is no manual selection step
- Files directly in the root (not in a subfolder) are ignored
- A subfolder with no audio files is ignored
- A subfolder whose name starts with `_` is ignored (reserved for internal use, e.g. archived ZIP imports)
- Recognised audio formats: `.mp3` `.flac` `.aac` `.m4a` `.wav` `.ogg` `.opus` `.aiff` `.aif`
- A previously selected root folder is remembered across app restarts
- On app launch, and when the refresh button is tapped, the directory is synced with the database: a release is added for every subfolder not yet known, and a release is removed for every known release whose subfolder no longer exists on disk
- Removing a release because its folder is gone preserves its tags and activity history in the database, keyed by folder path, in case the folder reappears
- A release already known to the database and still present on disk is left untouched by a sync — its tracks, metadata, and artwork are not re-scanned
- When a release is newly discovered, a track is added for every audio file in its folder, ordered by filename, with a title derived from the filename (leading track-number prefixes like `01 - ` or `02. ` are stripped); no other metadata is read yet
- When a release is newly discovered, only its first track (by filename) is downloaded; its embedded album artist/album title metadata is read from it, and it is evicted again afterwards — the rest of the release's tracks are left untouched
- Reading the first track's embedded metadata during a scan only informs the release-level album artist/album title — the track's own title/artist/track-number stay filename-derived, the same as every other track, until it is actually played (see Audio metadata)
- If a release's first-track download times out, the release is still created (using filename-derived tracks and the folder name as a fallback), and is retried on a future sync rather than left permanently unresolved
- Album artwork for a newly discovered release is resolved from a folder image file first (no download needed), then from the first track's embedded artwork once it has downloaded; a MusicBrainz lookup is not attempted during a scan
- A newly discovered release is assigned an activity timestamp at discovery time, so it sorts to the top of the library until played

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
- A MusicBrainz Cover Art Archive lookup (by album artist/title, preferring the earliest release date, fetched at the release-group level so any edition's scanned cover satisfies the lookup) exists as a fallback for when neither a local file nor embedded artwork is found, saving the result as `cover.jpg` in the release folder — currently not triggered by anything (library scanning explicitly skips it); an on-demand trigger from the release screen is planned but not yet implemented
- If neither a file nor embedded artwork is available, `artPath` is null and a placeholder is shown
- A release card shows a square thumbnail of the cover art (or placeholder) on the left
- The release screen shows the cover art as a full-width header above the track list
- The mini player shows a small thumbnail next to the track and album name

## Audio metadata

- A track's title and track number initially come from its filename (see Library scanning) — its embedded metadata tags are not read until the track is first played
- The first time a track is played, its embedded metadata tags (ID3, FLAC, M4A, etc.) are read and replace the filename-derived title, track number, and artist in the database; if a tag is empty, the filename-derived value is kept
- A track whose metadata has already been read is not re-read on later plays
- Album title and album artist are read from the first track's metadata during the initial scan (see Library scanning), not from any other track
- When both album artist and album title are present, the release name is displayed as "{albumArtist} - {albumTitle}"
- When metadata is absent, the release name falls back to the folder name
- Track artist is shown alongside the track title in the release screen track list
- Album artwork is shown on the lock screen and in the Now Playing controls

## Release data

- A release has a folder path, a name, a list of tracks, a list of tags, an optional art path, an optional album title, and an optional album artist
- Copying a release with new tags preserves all other fields
- A track has a file path, a title, a track number, an optional duration, an optional artist, and whether its metadata has been read from the file yet

## Playback

- Tracks are loaded and played one at a time, in release track order, regardless of local availability at the moment playback starts — the full track list is the queue, not just the currently-available subset
- Before loading a track, its local availability is checked; if it is not locally available, an iCloud download is requested for it and playback pauses (showing a buffering/waiting state) until it becomes available, then playback starts automatically without further user action
- Requesting to play any track (Play All, tapping a specific track, or skipping to the next/previous track) also requests an iCloud download of the whole release, not just the requested track — this happens on every such request, even if the requested track is already locally available, so the rest of the release keeps downloading in the background
- The mini player (and the Now Playing screen, if open) appears as soon as a track is requested, not only once it is actually loaded into the player — tapping a track that needs to download gives immediate visual feedback rather than appearing to do nothing until the download finishes
- While the player is waiting for a track to download, the mini player's and Now Playing screen's play/pause control is replaced by a spinner; previous/next controls remain available
- While the player is waiting for a track to download, the corresponding row in the release screen shows a spinner in place of its track number
- The first time a track is confirmed locally available, its embedded metadata is read and persisted to the database (see Audio metadata) before it starts playing, so the title shown from the very start of playback is the corrected one, not the filename-derived guess
- While a release plays, the rest of its tracks are also checked periodically for ones that have finished downloading in the background (from the whole-release request above) and still need their metadata read — this keeps correcting the rest of the album as it downloads, not only the track actually being played; it stops once every track's metadata has been read
- If a requested download does not complete within a timeout, a message is shown and playback automatically advances to the next track, as if the track had failed to play
- If a track that exists on disk still fails to play (e.g. a corrupt file), a message is shown and playback automatically advances to the next track
- A cancelled/superseded playback request (e.g. tapping a second track, or skipping, before the previous one finishes loading or downloading) does not show an error message and does not leave a stale buffering spinner showing
- Skip previous/next moves through the release's track order, not through play history, so skipping back from a track works even if the earlier track was never played this session
- If no track in the release is available and none can be downloaded, a message is shown and playback stops cleanly without looping or crashing
- Reaching the end of the release's last track stops playback and closes the mini player, rather than leaving it showing the last track as playing
- If playback stops because no further track could be played, the mini player closes the same way

## Mini player

- Visible at the bottom of every screen whenever something is playing or has been requested (even while still waiting for its first track to download)
- Shows current track title, album, and art thumbnail
- Shows the filename-derived track title until the track's real metadata has been read (see Audio metadata)
- Provides play/pause and skip controls; the play/pause control becomes a spinner while waiting for the current track to download
- Tapping it opens the Now Playing screen
- Sized for easy tapping: larger art thumbnail, text, and control icons than a standard compact bar, with generous padding

## Now Playing screen

- Opens full-screen from the mini player
- Shows full-size album art, release name, track title, and artist
- Shows the filename-derived track title until the track's real metadata has been read (see Audio metadata)
- Progress bar showing current position, scrubbable to seek
- Play/pause, previous, and next controls; the play/pause control becomes a spinner while waiting for the current track to download
- Dismissed by tapping the close button or swiping down
- Automatically closes itself if playback stops (e.g. the queue finishes or runs out of playable tracks) while it's open

## Library screen

- When no root folder has been selected, an empty-state prompt is shown with a button to choose a library folder
- When a root folder is selected but the library is empty (no valid subfolders found), an empty-state message is shown with a button to choose a different library folder
- When releases exist, one card is shown per release
- When an active tag filter has no matching releases, a "no releases match" message is shown
- The app bar has a button to choose a different library folder; it is disabled while a sync is in progress
- The app bar has a refresh button; tapping it re-syncs the directory with the database (see Library scanning); activity timestamps are not changed by a refresh
- While a sync is in progress (on launch or from the refresh button), the refresh button is replaced by a spinner in its place
- Already-known releases stay visible and tappable while a sync runs in the background, both on launch and from the refresh button — the list is not replaced by a full-screen spinner unless there are no releases to show yet
- As a sync discovers, removes, or resolves a release, the change appears in the list as soon as it happens, rather than only once the whole sync finishes
- Picking a different library folder does show a full-screen spinner until its first sync completes, since there is nothing from the previous folder worth showing

## Release screen

- Shows the release's current data from the database and updates itself automatically as that data changes (e.g. a background sync finishing its scan, or a track's metadata being read on first play) — it does not need to be reopened to reflect changes
- If the release is removed from the library while this screen is open (e.g. its folder disappears in a sync), the screen closes itself automatically
- If the release has no known tracks yet, the track list and "Play all" button are hidden and a message is shown instead; both appear as soon as tracks are known
- Each track's local availability (e.g. downloaded from iCloud or not) is checked when the screen opens
- While at least one track is not locally available, its availability is re-checked periodically (every 2 seconds) so a track that finishes downloading in the background — including one that isn't the currently-playing track — updates from a cloud icon to its track number without needing the screen to be reopened; this stops once every track is available
- A track's leading icon shows, in priority order: a spinner if it's the currently-playing track and its download is still in progress, an equalizer icon if it's the currently-playing track, a cloud icon if it's known but not locally available, or its track number if it's locally available
- All tracks are tappable regardless of local availability — tapping one that isn't downloaded triggers the same download-then-play behaviour described under Playback
- Every track row reserves space for the artist line even when no artist is known yet, so a row's height doesn't change (and the list doesn't visibly shift) when its metadata is read and it gains one

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
