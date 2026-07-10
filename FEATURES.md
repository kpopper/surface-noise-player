# Surface Noise Player — Feature Backlog

## Pending

- [ ] ZIP import — auto-scan iCloud Drive Downloads for ZIPs containing audio files; extract into library with ID3-derived `Artist - Album` folder names; archive source ZIP to `_zips/`; auto-select the new release
- [ ] Library management improvements - would like to see new additions to the library more easily, and would also like to be able to search to filter the list
- [ ] Add swipe gestures to navigate from mini player to Now playing and to minimise Now Playing window

## Completed

- [x] Skip buttons in player should relate to the tracks in the release, not the played tracks (e.g. if tapping on track 4, skip back should go to track 3, even if it hasn't been played)
- [x] Increase the size of the mini player to make it easier to tap — larger art thumbnail, text, and control icons, with extra bottom padding
- [x] Improve appearance of tags in the library — colour-coded text and filter chips; tags shown as plain coloured text (no pills) in release cards
- [x] Library management — per-album selection via a modal management screen; selecting downloads and scans an album, deselecting evicts it from local storage; unavailable releases (download timeout) recover automatically in the background
- [x] Sorting — sort library by most recent activity (played or added)
- [x] Now playing screen — full-screen player with progress bar and scrubbing
- [x] Quick scan — on launch and refresh, adds new folders and removes deleted ones without re-scanning existing releases
- [x] Remove debug logging — `[scan]` print statements in `lib/services/library_service.dart`
- [x] Album art — display cover art from a `cover.jpg`/`folder.jpg` (or any image file) in the release folder, or extract embedded artwork from audio metadata
- [x] MusicBrainz artwork — when no local art is found, automatically fetch 1200px cover art from MusicBrainz Cover Art Archive and save as `cover.jpg`; prefers earliest release date
- [x] Fix MusicBrainz artwork retrieval failing for some albums — fetch cover art at the release-group level instead of a single specific edition, since not every edition has a scan in the Cover Art Archive (was causing Tortoise's "Millions Now Living Will Never Die" and Geese's "Getting Killed" to show no cover)
