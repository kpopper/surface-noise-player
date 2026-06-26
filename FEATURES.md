# Surface Noise Player — Feature Backlog

## Pending

- [ ] ZIP import — auto-scan iCloud Drive Downloads for ZIPs containing audio files; extract into library with ID3-derived `Artist - Album` folder names; archive source ZIP to `_zips/`; auto-select the new release

## Completed

- [x] Improve appearance of tags in the library — colour-coded text and filter chips; tags shown as plain coloured text (no pills) in release cards
- [x] Library management — per-album selection via a modal management screen; selecting downloads and scans an album, deselecting evicts it from local storage; unavailable releases (download timeout) recover automatically in the background
- [x] Sorting — sort library by most recent activity (played or added)
- [x] Now playing screen — full-screen player with progress bar and scrubbing
- [x] Quick scan — on launch and refresh, adds new folders and removes deleted ones without re-scanning existing releases
- [x] Remove debug logging — `[scan]` print statements in `lib/services/library_service.dart`
- [x] Album art — display cover art from a `cover.jpg`/`folder.jpg` (or any image file) in the release folder, or extract embedded artwork from audio metadata
- [x] MusicBrainz artwork — when no local art is found, automatically fetch 1200px cover art from MusicBrainz Cover Art Archive and save as `cover.jpg`; prefers earliest release date
