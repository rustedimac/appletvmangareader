# iCloud sync and backup

The app is ready to sync through iCloud, but sync stays **off** until the app
is signed by a paid Apple Developer Program team with iCloud turned on. Until
then everything works as before, CI and sideloaded builds included, and
people can move their data with **Back Up and Restore over Wi‑Fi**.

## What syncs

| Synced | Not synced |
| --- | --- |
| Profiles (name, symbol, color) | Kavita API keys, Suwayomi usernames and passwords (Keychain only) |
| | Anything from a guest session (never saved) |
| Servers (name, kind, address) | Profile PINs, once that feature lands (#19) |
| Per profile and server: library/category choice, "sync progress to server" | Image caches |
| Favorites | Which profile is active on this device |
| Reading progress: position and every read/unread chapter | |
| Default reader settings and per-series reader settings (picture controls and split pages included) | |
| Home rows (order, hidden, merged or per-server rows, where posters name their server), poster size, poster caption, per-library sort, filters, reading direction and grid order; Library Defaults; Continue Reading removals; Caught Up | |

Logins stay on each device on purpose: the Keychain is the only safe place
for them, and iCloud Keychain sync would need its own opt-in. On a new
device, enter each server's key or password once.

Each Apple TV user has their own iCloud account, so with Apple TV users as
profiles (#18) every person syncs their own data with their own iPhone, iPad
or Mac version of the app later.

## How it works

Code: `Packages/MangaCore/Sources/MangaCore/Sync`, app side in
`App/Sources/Sync`.

- `SyncMapper` turns `AppState` into `SyncRecord`s, one per favorite, per
  series' progress, per profile, and so on, keyed `"<kind>/<id>"`. New
  features add a domain there with a new kind. Records of kinds a build
  doesn't know are left untouched in the cloud, so an older Apple TV build
  can't delete a newer iPhone app's data.
- `SyncMerge` has the rules: newest change wins per record (ties go to the
  larger device id, so every device picks the same winner); progress keeps
  the newest position and merges read marks chapter by chapter, including
  "marked unread". Deletions are tombstone records, so they sync like any
  change.
- `SyncEngine` runs a sync: fetch changes since the last change token,
  compare local state with the ledger of what was last synced, merge, apply,
  upload. Saves that race another device come back as conflicts, get merged
  with the cloud's copy and are saved again. Changes that can't upload wait
  in an offline queue (kept in UserDefaults with their original time); the
  ledger is a Caches file and can be lost safely (the next sync acts like a
  first sync).
- The first sync on a device adopts the cloud's ids for a profile with the
  same name and a server with the same kind and address, and moves its
  Keychain logins to match, so a fresh install's "Me" doesn't show up twice.
- `SyncStore` is the cloud side. `CloudKitSyncStore` uses the private
  database, one custom zone `MangaReaderSync`, one record type
  `SyncRecord`, `.ifServerRecordUnchanged` saves and a zone subscription for
  silent pushes. `LocalOnlySyncStore` is used when the build has no iCloud;
  `InMemoryCloudStore` is a fake iCloud for tests.
- `CloudSyncController` (app) syncs on launch, when the app becomes active,
  5 seconds after local changes, and on a silent push.
- `CloudSyncAvailability` decides whether CloudKit may be touched at all
  (CloudKit stops an app that uses it without the entitlement): the
  Info.plist key `MRCloudKitContainer` must hold an `iCloud.` container id,
  and a development build's provisioning profile must list it.

### Backup over Wi‑Fi

tvOS has no Files app or AirDrop, so Settings → iCloud Sync and Backup →
Back Up and Restore over Wi‑Fi starts a small web page on the Apple TV while
the screen is open. It shows an address like `http://192.168.1.20:8790/482913/`
and a QR code. From a phone or computer on the same network you can download
`manga-reader-backup-<date>.json` or upload one to restore. The six-digit
code changes every time the screen opens.

The backup is versioned JSON (`MangaBackup`, format `mangareader-backup`,
version 1) with the same records as iCloud. Restoring merges: favorites and
servers are added, the furthest reading position and every read chapter are
kept, settings take the backup's values, and nothing is deleted. An iPhone
or Mac version can read the same file.

## Turning on iCloud (John, once the membership is active)

1. **Join the Apple Developer Program** and wait for the membership to show
   as active at <https://developer.apple.com/account>.
2. **Create the container.** In Certificates, Identifiers & Profiles →
   Identifiers, pick the App ID `com.rustedimac.MangaReader` (Xcode creates it
   the first time you build with your team), tick **iCloud**, choose
   **CloudKit**, and create the container
   `iCloud.com.rustedimac.MangaReader`. Also tick **Push Notifications** so
   other devices' changes arrive right away (sync still works without it, on
   launch and wake).
3. **Edit `project.yml`** in the `MangaReader` target:

   ```yaml
   settings:
     base:
       DEVELOPMENT_TEAM: <your team id>
       MR_ICLOUD_CONTAINER: iCloud.com.rustedimac.MangaReader
   entitlements:
     path: App/MangaReader.entitlements
     properties:
       # keep any keys already here, e.g. com.apple.developer.user-management
       com.apple.developer.icloud-container-identifiers: [iCloud.com.rustedimac.MangaReader]
       com.apple.developer.icloud-services: [CloudKit]
       aps-environment: development   # production for TestFlight/App Store
   info:
     properties:
       UIBackgroundModes: [remote-notification]
   ```

   Then `xcodegen generate`. In Xcode, Signing & Capabilities should now
   list iCloud (CloudKit, with the container ticked) and Push Notifications
   without errors.
4. **Test on two devices** signed in to the same iCloud account (Apple TV
   plus the tvOS simulator works: sign the simulator in to iCloud in its
   Settings app). Settings → iCloud Sync and Backup should say "Up to date".
   Add a favorite on one, wait a few seconds (or press Sync Now on the other)
   and it appears on the other.
5. **Deploy the schema before release.** The first sync from a development
   build creates the `SyncRecord` type in the development environment. In
   the [CloudKit Console](https://icloud.developer.apple.com) → the
   container → Schema, check `SyncRecord` has `key`, `kind` (String),
   `payload` (Bytes), `modifiedAt` (Date/Time), `deviceID` (String) and
   `deleted` (Int64), add a **Queryable** index on `recordName` (lets the
   console browse records), then **Deploy Schema Changes** to Production.
   TestFlight and App Store builds use Production and fail to save until
   this is done.
6. Ship with `aps-environment: production`.

To turn sync back off for a build, set `MR_ICLOUD_CONTAINER` back to `""`.

## Follow-ups

- Content filters and PINs (#19), page bookmarks (#14), the read-sync
  pending queue and Continue Reading series (#15) and the remembered profile
  (#18) add or change fields after this lands. Each feature adds a domain to
  `SyncMapper` (PINs stay out of iCloud); `SyncRemap` also needs to rewrite
  the server id inside `SeriesProgress.series` once #15 merges.
- Servers shared between Apple TV users (#18) come from the user-independent
  Keychain; sync keeps each user's copy in their own iCloud.
- Optional: offer iCloud Keychain for logins (synchronizable Keychain items)
  as a separate opt-in.
