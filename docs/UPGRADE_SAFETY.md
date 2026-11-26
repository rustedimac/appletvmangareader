# Upgrade safety

An app update must never wipe what people saved: servers, logins, profiles,
settings, reading progress, bookmarks or favorites. This page lists what the
app saves, the rules for changing it, and the tests that enforce them.

## What is saved

| Data | Where | Type | Fixture (`Tests/MangaCoreTests/Fixtures/SavedData`) |
| --- | --- | --- | --- |
| Profiles, servers, favorites, progress, bookmarks, reader/book/browse settings | UserDefaults `mangareader.appstate.v1` | `AppState` | `appstate-v1-*.json` (older shapes inline in `AppStateUpgradeTests`) |
| Servers shared by every Apple TV user, with the first login for each | user-independent keychain | `SharedServerDirectory` | `shared-servers-v1.json`, `shared-servers-v2.json` |
| Logins, per profile and server | keychain | `ServerCredential` | `credentials-v1.json` |
| Place inside a book chapter | UserDefaults `mangareader.bookpositions.v1` | `[String: BookPosition]` | `book-positions-v1.json` |
| iCloud offline queue | UserDefaults `mangareader.sync.journal.v1` | `SyncJournal` | `sync-journal-v1.json` |
| Backup files people export | a file | `MangaBackup` | `backup-v1.json` |

Not covered on purpose, because they are rebuilt: the iCloud sync ledger
(Caches), the Top Shelf snapshot (rewritten on every launch), image caches.
Small flags (`mangareader.icloud.enabled`, reader hint counts) are plain
booleans and numbers.

## Rules

1. **Decode tolerantly.** Every saved type has an `init(from:)` built on the
   helpers in `Storage/TolerantDecoding.swift`: `tolerant(_:default:)`,
   `tolerant(_:)`, `tolerantArray`, `tolerantDictionary`. A field that is
   missing (saved before it existed) or holds a value this build doesn't know
   (an enum case from a newer build, or one you removed) falls back to its
   default. Only identity is required: ids, a series' `ref`, a server's kind
   and address, a position's chapter and page.
2. **One bad entry costs that entry, never the list.** Lists and
   dictionaries of entries use `tolerantArray` / `tolerantDictionary`, or in
   `AppState` the salvage pass in `AppStateUpgrade` (which also keeps the
   original bytes under `StateStore.backupKey`).
3. **Add a snapshot whenever you change what is saved.** Copy the newest
   fixture to a new file named for today (`appstate-v1-YYYY-MM-DD.json`),
   add your field as the app writes it, and append the name to
   `SavedFormats.appStateFixtures`. Never edit an existing fixture: it is what
   people's Apple TVs hold. Other formats: add `<name>-v2.json` beside the
   old one and point the test at both.
4. **Classify the field for sync** in `SyncCoverageTests` (synced, local, or a
   known gap).
5. **Renames and moves** bump `AppState.currentVersion` and add an
   `AppStateUpgrade.step` that rewrites the old shape. Never drop data in a
   step.
6. **Fixtures are fictional.** Made-up titles, generic hosts
   (`kavita.local`), fake keys. Never real servers, keys or manga titles.

## The tests

`SavedDataUpgradeTests` runs these checks on every fixture:

- **Loads without salvage**, and re-saving keeps it.
- **Every field may be missing**: each field is removed in turn (everywhere
  it appears) and the rest of the data must come back unchanged. Fields that
  are allowed to be required are listed in
  `SavedFormats.requiredAppStateFields`.
- **Unknown values don't lose entries**: each string value is replaced with
  one no build knows, and no profile, server, favorite, bookmark, progress
  entry or list item may be lost. Exceptions, with reasons, are in
  `SavedFormats.unknownValueLosses`.
- **The newest fixture covers every field**: every field of every saved
  MangaCore type must be set somewhere in it, and the app may not write a
  key the fixture lacks. This is the check that fails when you add a field
  without a snapshot.

`AppStateUpgradeTests` covers migration, salvage, garbage data and
downgrades (state from a newer build). `SyncCoverageTests` covers the sync
classification. `MangaBackupTests` and `testBackupRestoresIntoAFreshInstall`
cover backup files.
