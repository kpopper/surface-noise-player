# Surface Noise Player — Feature Backlog

## Pending

- [ ] ZIP import — auto-scan iCloud Drive Downloads for ZIPs containing audio files; extract into library with ID3-derived `Artist - Album` folder names; archive source ZIP to `_zips/`; auto-select the new release
- [ ] Add swipe gestures to navigate from mini player to Now playing and to minimise Now Playing window
- [ ] Improve "Play all" button functionality - maybe not needed: just play first track
- [ ] Tweak design of tag lozenges: more pronounced text (bold?), replace "Clear" button with de-selection by tapping selected tag
- [ ] Notify user once if a release cannot be downloaded when attempting to play
- [ ] App needs a proper icon
- [ ] Flash of empty library screen when first opens
- [ ] Allow user to "download" releases explicitly (keep a release downloaded / auto-re-download on app start etc)
- [ ] Fall back to the iTunes Search API (and possibly Discogs) for cover art when MusicBrainz has none

## Completed

- [x] Library redesign — replaced the select/deselect model with "the library is everything on disk": directory scan/sync data layer (releases added/removed automatically, first-track-only scan for album info, old management screen removed), per-track download-on-play (request-on-tap, buffering spinner, whole-release download requested on every play action, metadata read and persisted the first time a track is confirmed available, release screen live from the database), and the main library screen (name search field with tap/scroll-to-dismiss keyboard, a toggle between recency and alphabetical sort order, all releases tappable regardless of download status, dead `isAvailable` greying-out removed)
- [x] Library management improvements — search field to filter the folder list by name; already-selected albums shown in bold so new/unselected ones stand out
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
- [x] Restore MusicBrainz artwork lookup, lost in the library redesign rewrite — fixed a wrong-album match (missing `AND` between query clauses let same-artist/different-album results win the earliest-date tiebreak), a stale Flutter image-cache entry masking successfully-resolved artwork, and a long-lived `http.Client` going stale after sitting idle; added a single on-demand retry when opening a release with no artwork, and a track-artist-tag fallback for releases with no album-artist tag (common on ripped CDs)
- [x] Bulk artwork retry from the refresh button — sweeps every fully-scanned release still missing artwork, in addition to the regular directory sync, rate-limited to the MusicBrainz API's ~1 req/sec so it's safe regardless of how many releases need retrying
- [x] Artwork retry reliability fixes — retry paths (on-demand and bulk) now check embedded artwork before MusicBrainz, so releases with artwork that MusicBrainz can't find still resolve; a release's own failure no longer aborts the rest of a bulk sweep; a still-unresolved release's repeated re-scan no longer regresses an already-found `art_path` back to null; embedded artwork is now persisted into the release's own folder like a MusicBrainz download, instead of the app's own internal storage, so it survives an app reinstall
- [x] Allow a release's metadata to be rescanned — a manual "Rescan metadata" button on the release screen re-reads the first track's tags and re-resolves artwork exactly as during initial discovery, treating the file's tags as the source of truth and overwriting whatever was previously stored; also fixed a MusicBrainz tiebreak bug found in the same investigation (a same-titled single sharing an album's exact title could win the earliest-date tiebreak over the album itself)
- [x] Don't evict first track after scanning metadata if it was already downloaded — a scan/rescan/artwork-retry now only evicts the first track afterward if it downloaded it itself; also fixed the release screen's cloud icon getting stuck stale after such an action, since iOS eviction is only a request and may not take effect immediately
- [x] Fix native forward and back track on iOS — replaced `just_audio_background`'s bundled media-session handler (which only enabled native skip based on `just_audio`'s own single-item playback queue) with a custom `AudioHandler` via `audio_service` directly, wiring native skip to the same queue-navigation the on-screen skip buttons already use
