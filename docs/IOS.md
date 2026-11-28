# iPhone and iPad

The plan and the rules for the iOS / iPadOS app. The tvOS app stays the
reference: everything it can do, the iOS app does too, with touch idioms
instead of the Siri Remote. Status of each step is in section 9.

## 1. Decisions

| | Decision | Why |
| --- | --- | --- |
| Targets | A second app target, `MangaReaderiOS` (iPhone + iPad, `TARGETED_DEVICE_FAMILY 1,2`), next to the tvOS `MangaReader`. Same scheme layout: scheme `MangaReaderiOS` with its own UI test target `MangaReaderiOSUITests`. | One Xcode project, one MangaCore, no fork. A Mac Catalyst / macOS build can follow later on the same seam. |
| Bundle id | `com.rustedimac.MangaReader` for both apps. | Universal Purchase on the App Store later: one listing, one purchase, one iCloud container. |
| Minimum OS | iOS / iPadOS 18.0. | `TabView` with `.sidebarAdaptable` (iPad sidebar / iPhone tab bar), `Tab` API, zoom navigation transition. Every iPhone that runs iOS 18 is supported. |
| Shared code | Every file under `App/Sources` compiles for both platforms unless it is in the iOS target's `excludes` list. Platform-only code goes in `App/Sources-iOS/` (iOS only) or stays tvOS-only behind `#if os(tvOS)`. | Screens, models, readers' sessions and settings are the same features; only input and layout differ. |
| Platform seams | `App/Sources/Shared/Platform/` holds the shims (`tvFocusSection()`, `posterButtonStyle()`, `Platform.isTV`, …). Shared views call the shim, never a tvOS-only API directly. Inline `#if os(tvOS)` inside a modifier chain is fine for one-offs. | Keeps tvOS behaviour byte-for-byte the same while iOS gets the touch version. |
| Design tokens | `DesignTokens.swift` keeps its names; values switch per platform (`#if os(tvOS)` for the 1920 × 1080 canvas, otherwise iOS values in points, iPad wider than iPhone via size class where a token needs it). | Screens keep using `Space.l`, `Grid.posterWidth`, … and get sensible sizes on a phone. |
| Settings layout | `SettingsPage` on iOS is a plain inset-grouped `Form` with a large navigation title (the tvOS hero column is tvOS only). | iOS HIG: navigation titles collapse into the bar, nothing pins over rows. |
| Profiles | iOS has no per-user app data, so in-app profiles are the profile system (the tvOS fallback). `SingleUserDevice` identity. "Who's reading?" shows at launch only with several profiles, like the tvOS fallback. | `DeviceUserIdentity` is already the seam (docs/ARCHITECTURE.md). |
| iCloud | Same `CloudSyncController`, still off until the paid membership (empty `MR_ICLOUD_CONTAINER`). When it is on, the iPhone, iPad and Apple TV share one container, so favorites, progress and bookmarks follow the person. | docs/ICLOUD.md |
| Backup | iOS replaces the Wi-Fi backup web page with Files: Export Backup (`fileExporter`, `.mangabackup` JSON) and Import Backup (`fileImporter`). Same `MangaBackup` format both ways, so a phone backup restores on the TV page and vice versa. | iOS has Files; the TV doesn't. |
| Phone setup (QR) | Not on iOS: the phone *is* the keyboard. The server editor hides "Set Up from Your Phone". | |
| Top Shelf | tvOS only. The iOS target leaves out `TopShelfPublisher` and the extension; deep links (`mangareader://`) still work on iOS. | |
| App Groups / user-management entitlements | tvOS only. The iOS app has no entitlements until iCloud is turned on. | A free (Personal Team) provisioning profile can't hold App Groups or iCloud; this keeps the iOS app installable without the paid membership. |
| Game controllers | Shared: `GameControllerHub` works on iOS too (MFi / Xbox / PlayStation pads, same mapping). | Free feature, same code. |
| Reader input | Touch-first (section 3). Remote-only code (`ReaderRemoteCatcher`, `TouchSurfacePan`, `onMoveCommand`) stays tvOS only. | |
| Orientation | Every orientation on iPad and iPhone. The reader can lock orientation from its options (per series, with a global default, like every per-series setting). | |
| Look | System light/dark on iOS (the tvOS app is dark only). The reader is always dark-backed (its own background setting). No custom app themes (removed 2026-11-28). | |

## 2. Navigation

- **iPhone**: bottom tab bar with Home, Library, Favorites, Bookmarks, Search, Settings (Search uses the iOS 18 search tab role, so it sits on its own). Each tab is a `NavigationStack` with large titles.
- **iPad**: the same `TabView` with `.sidebarAdaptable`: a tab bar at the top that the person can turn into a sidebar listing servers and libraries. In Split View and Slide Over the window gets compact width and the app switches to the iPhone layout by size class, not by device.
- The reader opens as a `fullScreenCover` from series detail on both (it already does on tvOS). On iPad the cover takes the whole window, never a sheet.
- Swipe back works everywhere (no custom back buttons). Swipe down on the reader's chrome-hidden page does nothing (no accidental dismiss); the close button and the chrome's back arrow close it.
- iPad hardware keyboard: ← / → / space turn pages, ↑ / ↓ scroll the vertical reader, Esc closes the reader options then the reader, ⌘F opens Search, ⌘, Settings (`.keyboardShortcut`).

## 3. Reader on touch

Same `ReaderSession`, `ReaderNavigator`, `SpreadLayout`, `ReaderSettings` as tvOS. New for touch:

| Action | Paged | Vertical | Book |
| --- | --- | --- | --- |
| Tap centre | show / hide the chrome (top bar: back, title, chapter, bookmark, options; bottom: page slider + page number) | same | same |
| Tap left / right third | previous / next page (direction follows reading direction; right-to-left manga flips them) | scroll one screen up / down | previous / next page |
| Swipe left / right | turn page (interactive, follows the finger) | — | turn page |
| Pinch | zoom 1x to 4x, page pans while zoomed, turns disabled until back at 1x | zoom the strip (columns stay joined) | text size |
| Double-tap | zoom to 2x at the tap point / back to fit | same | — |
| Long-press a page | page menu: bookmark this page, share the page image | same | — |
| Drag the bottom slider | scrub pages (the tvOS scrubber's thumbnails above it) | jump | jump |

- Tap zones are a reader setting, `tapZones` (per series, with a global default in Default Reader Settings, per the rule that every per-series setting has a global default): **Edges** (default: left/right thirds turn, centre toggles chrome), **Left-handed** (both side zones go forward), **Off** (taps only toggle the chrome). Shown in the options on iOS only.
- Two-page spreads: on by default in landscape, off in portrait on iPhone (`ReaderSettings.spreads` keeps its meaning; `SpreadLayout` is told whether the container is landscape). iPad portrait shows single pages unless the person turns spreads on.
- The options open as a sheet on iPhone (medium / large detents) and a popover from the options button on iPad, built from the same rows as the tvOS menu (`ReaderMenu` sections), touch sized.
- Status bar and home indicator hide with the chrome (`.statusBarHidden`, `.persistentSystemOverlays(.hidden)`).
- Idle timer stays off while the reader is open (already done for auto-scroll).
- Play / auto-advance stays (Play button in the chrome) for the vertical auto-scroll and the paged page timer.

### As built (step 2)

- Rules live in MangaCore `ReaderTouch` (unit tested): `tap(_:zones:mode:direction:zoomed:)`, `swipeTurn`, zoom clamp (1x to 4x), double-tap target, `effectiveLayout` (portrait = single pages; the saved layout is untouched, `ReaderSession.layoutSettings`).
- `ReaderSettings.tapZones` (`TapZones`: edges, leftHanded, off), saved per series with its row in Default Reader Settings (iOS only) and in the reader options (`ReaderMenuOptions.items(for:touch:)`). Snapshot `appstate-v1-2026-11-27-tapzones.json`.
- While zoomed, side taps only toggle the chrome. Two taps within the double-tap interval count as a double-tap (zoom), so a side tap waits that long before turning; swipes don't.
- Books use the profile's default Tap Zones (books have no per-series reader settings).
- The vertical reader scrolls with a finger (its pan recognizer takes direct touches on iOS, gain 1); side taps scroll `webtoonScrollStep` of a screen.
- Choices on iOS (reader options and every `SettingsPicker`) are `MenuValueRow`s: name on the left, value and an up/down chevron on the right, opening the system pop-up menu with a checkmark, like iOS Settings. The TV's in-place choice list (`PanelChoiceList`) is tvOS only.
- Options: the same `ReaderMenu` / `BookReaderMenu` panels in a popover from the chrome's options button, a sheet (medium / large) on iPhone, with a Done button.
- Polish (after step 6): long-press a page for Bookmark / Share Page (`ReaderPageMenu`, system share sheet with the page image); `ReaderSettings.orientationLock` (Follow Device / Portrait / Landscape, per series with its default in Default Reader Settings, snapshot `appstate-v1-2026-11-27-orientation`; iPhone only, since an iPad app that supports Split View can't lock its orientation; `OrientationGate` + the app delegate); the vertical reader's column fills a portrait window (`ReaderTouch.effectiveWebtoonWidth`, Column Width applies in landscape).
- iPad sidebar: a Servers section under the tabs opens each server's library (sidebar only, `TabSection` hidden from the tab bar). The page slider shows a thumbnail of the page under the finger while it moves.
- Not yet: pinch in the vertical and book readers (the vertical reader fills the width in portrait instead).

## 4. Layout

- Poster grids use `GridItem(.adaptive(minimum:))` with a minimum from the token (`Grid.posterWidth`: 110 pt iPhone, 150 pt iPad, 217 tvOS) so the column count follows the window, including Split View and Stage Manager resizing.
- Home rows: horizontal scroll rows of posters, as on tvOS, with smaller posters and the row title as a button to the full list.
- Series page: compact width stacks cover over details; regular width puts the cover on the leading side and the chapter list on the trailing side.
- Settings: inset-grouped `Form`, standard iOS rows (`LabeledContent`, `Picker` with `.menu` / `.navigationLink` styles). `SettingsPicker` on iOS is a system `Picker` in navigation-link style.
- Dynamic Type: every text uses text styles already (lint `check_design_tokens.py`); layouts must survive the accessibility sizes (rows wrap, grids drop columns).

### As built (step 3)

- Poster sizes per device: `GridDensity.points` / `spacingPoints` (iPhone 80 / 100 / 150, iPad 120 / 150 / 190; tvOS unchanged). `PosterMetrics` and `Grid.posterWidth` follow them.
- Browse tabs get side margins (`browseMargins()`, safe-area padding so shelves still run to the screen edge) and large titles (`browseTitle(_:)`); a server's library page shows its name in the bar instead of a heading.
- Series page: compact width puts a 120 pt cover beside the title and the rest below, with Continue as a full-width prominent button and bordered Favorite / sort / More under it; chapter rows put pages and date under the title. Regular width keeps the TV layout at 220 pt.
- A–Z jump bar: a narrow iOS-style index.
- iPhone: Bookmarks opens as a sheet from a button in Favorites.
- `platformValue(tv:touch:)` for one-off spacings; the tvOS numbers are the old ones.
- Servers are listed in the iPad sidebar (polish, see §3 "As built").

### As built (step 4)

- `FilesBackupView` (App/Sources-iOS): Export Backup (`fileExporter`, a `.json` file named "Manga Reader Backup <date>", so Files, AirDrop and Mail open it without a custom type) and Restore from a Backup File (`fileImporter`). Same `MangaBackup` format as the Apple TV page.
- Server editor: no "Set Up from Your Phone" on iOS. Settings: no Remote and Controller page; the reader's controls tutorial isn't offered; remote hints and the Siri Remote legend are tvOS only.
- Text: "this Apple TV" reads "this iPhone" / "this iPad" (`Platform.deviceName`), retry hints say "Tap to retry", empty Bookmarks and Search explain the touch way.
- The app follows the system's light or dark setting on iOS. The reader stays dark-backed.
- Profiles: in-app profiles with `SingleUserDevice` (from step 1); "Who's reading?" shows only with several profiles.

## 5. Files and local content

- **Open from Files** (phase 2, after the release build): CBZ / ZIP / PDF / EPUB picked with `fileImporter` or opened from the share sheet go into an on-device "On This iPhone" source, read with the existing `ZipArchive`, PDF and book readers. Not needed for the first device build.
- PDF pages render with PDFKit on iOS (CoreGraphics on tvOS stays the TODO in BOOKS-AND-PDF.md).

## 6. Signing and getting it on a device

| Route | Needs | Limits |
| --- | --- | --- |
| Xcode / `devicectl` install with the free Personal Team | Apple ID signed in to Xcode, the device plugged in once (then Wi-Fi), Developer Mode on the device | Profile expires after **7 days** (re-install from the Mac to renew), at most 3 apps per device, no iCloud / App Groups / push. Fine for testing. |
| TestFlight | Paid Apple Developer Program membership | 90-day builds, up to 10,000 testers, needed before the App Store. |
| Ad-hoc .ipa | Paid membership (device UDIDs in a profile) | |

The first test build uses the Personal Team route: the maintainer's Mac builds the `MangaReaderiOS` scheme with `DEVELOPMENT_TEAM` set to the Personal Team and `-allowProvisioningUpdates`, and installs with `xcrun devicectl device install app`. Steps in [IOS_DEVICE.md](IOS_DEVICE.md).

## 7. Tests

- MangaCore: unchanged, runs on macOS; iOS-only logic (tap zones, spread orientation rule) goes in MangaCore with `swift test` coverage.
- `MangaReaderiOSUITests`: an iPhone smoke set and an iPad smoke set (launch, tabs, server editor with demo servers, open the demo reader, tap zones turn pages, pinch zoom, chrome toggle, rotation). Same `-uiTesting`, `-readerDemo`, `-demoServers` flags as tvOS.
- CI: a `ios` job builds the iOS app for the simulator on every PR (build only, a few minutes) and runs the iOS smoke UI tests on main / nightly. The tvOS jobs don't change.
- TESTING_GUIDE.md gets section 3.12 "iPhone and iPad" with check IDs `IOS-xx` and device rows for L5.

## 8. Order of work (PRs)

1. **iOS foundation**: this doc, the iOS target and scheme, platform shims, per-platform tokens, iOS root navigation, everything compiling and launching on iPhone and iPad simulators; tvOS unchanged. CI builds iOS.
2. **Touch reader**: tap zones, swipe, pinch and double-tap zoom, chrome with slider, options sheet/popover, orientation-aware spreads, keyboard shortcuts.
3. **iPhone and iPad layouts**: adaptive grids, series page, Home rows, settings on iOS, sidebar, Split View.
4. **iOS system pieces**: Files backup export/import, hide phone setup, profiles on iOS, light/dark.
5. **iOS UI tests + TESTING_GUIDE section, simulator pass on iPhone and iPad.**
6. **Device build**: IOS_DEVICE.md, a signed build installed on the maintainer's iPhone.
7. Later: Open from Files source, PDFKit pages, App Store assets (only after "release ready").

## 9. Status

| Step | State |
| --- | --- |
| 1 Foundation | built; iPhone + iPad smoke tests pass on simulators |
| 2 Touch reader | built; iPhone + iPad touch UI tests pass on simulators |
| 3 Layouts | built; browse screens, series page and library grid checked on iPhone and iPad simulators |
| 4 System pieces | built; Files backup, no phone setup, system light/dark, iOS wording |
| 5 Tests | |
| 6 Device build | |
