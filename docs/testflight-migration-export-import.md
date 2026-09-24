# Library export/import for an app identity migration

Used once, during the #42 TestFlight bundle-ID migration (moving from
`com.iankynnersley.surfaceNoisePlayer` to
`com.iankynnersley.surfaceNoiseMusicPlayer` under a new Apple developer
account), to carry the library database across to the fresh install a
bundle-ID change produces. Confirmed working end-to-end on-device, then
removed from the codebase since it was only ever needed for that one
migration on one device — no other install needed it, and there's no
ongoing reason to carry the extra surface area permanently. This document
exists so the same approach can be rebuilt quickly if a future account/
bundle-ID change (or a second device migration) needs it again.

## The problem

A bundle ID change makes iOS treat the app as a brand-new app — its local
SQLite database (tags, activity timestamps, resolved release/track
metadata, artwork paths) starts empty. The actual audio files, folder
structure, and cover art are unaffected, since the library root is a
user-picked folder (via `UIDocumentPickerViewController` + a
security-scoped bookmark, see `bookmark_service.dart`) living outside the
app's own iCloud container — so a fresh install can rediscover them by
folder-scanning, but loses everything that only lived in the database.

## Why path portability isn't an issue

Neither `Release.folderPath` nor `Track.path` carry any OS-assigned
absolute-path identity that needs to survive across installs. Both are
built as plain string joins — `rootPath + folder name` and
`rootPath + folder name + file name` — computed fresh from whatever
`rootPath` the *current* app session resolves when the folder is picked
(see `LibraryService._listTracksQuick` and `syncLibrary`, both of which
just call `Directory(path).list()` and use the returned `.path` directly,
with no canonicalization). So as long as export/import data is keyed by
relative folder/file **name** rather than full path, and import
reconstructs full paths by joining against the *newly resolved* rootPath,
the reconstructed paths match byte-for-byte what a live scan of that same
folder computes — regardless of what the underlying absolute path
resolves to on a given device or under a different bundle ID/app
container. The one real requirement: folder and file names must be
unchanged between export and import (a rename in between breaks the
match).

## Export file

A JSON file written to the *root* of the library folder itself (not
inside the app's storage), so it travels with the library and is picked
up by whatever app next scans that folder. Root-level files are already
ignored by scanning (`CAPABILITIES.md` — "Files directly in the root...
are ignored"), so it's inert to the running app otherwise.

Read straight from the database at export time (not from whatever's
loaded in the UI), so it reflects the fully-resolved state:

```json
{
  "version": 2,
  "exportedAt": "2026-09-24T12:00:00.000",
  "releases": {
    "Artist - Album": {
      "name": "Artist - Album",
      "albumTitle": "Album",
      "albumArtist": "Artist",
      "artFileName": "cover.jpg",
      "firstTrackScanned": true,
      "tags": ["jazz", "favourite"],
      "lastActivityAt": 1751000000000,
      "tracks": [
        {
          "fileName": "01 - Song.mp3",
          "title": "Song",
          "trackNumber": 1,
          "artist": "Artist",
          "metadataRead": true
        }
      ]
    }
  }
}
```

Keyed by release folder name, then track file name — both relative, per
the portability note above. `albumTitle`/`albumArtist`/`artFileName`/
`lastActivityAt`/track `artist` are omitted when not set, rather than
written as `null`.

## Import behaviour

Triggered automatically and silently the first time a library folder is
picked on a fresh install (no library root previously saved) — this is
the one moment it's safe to assume any export file found is meant for
*this* install, since a returning user re-picking their existing folder
should never have current tags/activity silently overwritten by an old
export.

Import does two things:

1. **Tags and activity** — applied directly via the existing
   `DatabaseService.addTag` / `setLastActivity`.
2. **Releases and tracks** — restored directly into the `releases` and
   `tracks` tables (`saveRelease`, `markFirstTrackScanned`, `saveTracks`,
   `markTrackMetadataRead`), reconstructing `folderPath`/`file_path` by
   joining the export's relative names against the newly-resolved root.

Point 2 is what makes this worth doing over a tags-only export: the
following library sync (`LibraryService.syncLibrary`) already treats any
release that's both known-to-the-database *and* still present on disk as
untouched — no re-download, no re-scan — unless explicitly rescanned. By
restoring full release/track rows (including `first_track_scanned`)
*before* that sync runs, every already-known release is skipped entirely,
so the expensive part of a first scan (downloading each release's first
track from iCloud, then a MusicBrainz lookup capped at 1 request/second,
then an iTunes Search API fallback capped at 1 request/3 seconds) never
runs again for anything already captured in the export. The sync still
runs as normal afterwards and reconciles any genuine drift since export —
new folders get discovered and scanned the normal way, folders that have
disappeared get removed. An export entry with no `tracks` key (e.g. an
earlier tags-only export format) only has its tags/activity applied,
leaving release/track creation to the following sync as usual.

Artwork itself needs no special handling or transfer: every artwork
source the app resolves (folder image, embedded-and-extracted, MusicBrainz,
iTunes) is saved as a file *inside the release folder itself*
(`cover.jpg`), specifically so it survives an app reinstall — so
`artFileName` just needs to be re-joined against the folder path, not
copied or re-fetched.

## Where the code lived (for reference, not currently in the tree)

- `lib/services/migration_export_service.dart` — `MigrationExportService`
  with `exportTo(rootPath)` and `importIfPresent(rootPath)`, both reading/
  writing through `DatabaseService`.
- `lib/services/library_provider.dart` — `pickFolder()` called
  `importIfPresent` only when no root was previously set; a separate
  `exportForMigration()` method for the manual export trigger.
- `lib/screens/library_screen.dart` — a temporary app bar button
  ("Export for migration", share icon) calling `exportForMigration()`,
  only shown once a root is selected.
- Tests: `test/unit/services/migration_export_service_test.dart` (seeded
  the database directly via `DatabaseService`, mirroring a real scan, then
  asserted the export JSON shape and the round-trip restore), plus cases
  in `test/unit/services/library_provider_test.dart` for the `pickFolder`/
  `exportForMigration` hooks, backed by `test/helpers/fake_migration_export_service.dart`.

## Result

Exported from the old-bundle-ID install (full library, tags, and recency
order already established), then imported on a fresh install of the new
bundle ID: tags and recency ordering came through intact, and releases
populated immediately rather than triggering a full rescan.
