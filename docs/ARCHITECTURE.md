# Architecture

## Layout

| Path | What lives there |
| --- | --- |
| `Packages/MangaCore` | Swift package with all non-UI logic. No SwiftUI. Tested with `swift test`. |
| `MangaCore/Models` | Shared value types: `ServerConfig`, `Profile`, `SeriesSummary`, `SeriesDetail`, `Chapter`, `PageDescriptor`, `HomeFeed`. |
| `MangaCore/Networking` | `HTTPClient`, `HTTPTransport` (mockable), and the `MangaServer` protocol every backend implements. |
| `MangaCore/Kavita` | `KavitaClient` (REST, API key → JWT via `api/Plugin/authenticate`) and `KavitaOPDS` URL parsing. |
| `MangaCore/Suwayomi` | `SuwayomiClient` (GraphQL at `/api/graphql`, optional basic auth). |
| `MangaCore/Storage` | `AppState` (profiles, servers, per-profile favorites / progress / reader settings), `StateStore` (UserDefaults JSON), `SecretStore` (Keychain). |
| `MangaCore/Images` | `ImagePipeline` (`ImageLoading`): authorized image fetch, ImageIO downsampling, memory + disk cache, shared downloads, prefetch with original pixel sizes. Views use `RemoteImage` in `App/Sources/Shared/Images`. |
| `MangaCore/Reader` | `ReaderSettings`, `SpreadLayout` (two-page pairing), `ReaderNavigator` (page turns, chapter edges, re-layout anchoring, preload order) and `SpreadGeometry` (seamless spread frames). |
| `App/Sources/Shared` | `AppModel`, the `@Observable` app model in the SwiftUI environment, plus shared views. |
| `App/Sources/<Tab>` | One folder per tab: Home, Library, Favorites, Search, Settings. |
| `App/Sources/Reader` | `ReaderView` (entry point) and `ReaderSession` (shared reader state and progress saving). `Paged/`, `Webtoon/` and `Menu/` hold the paged reader, the vertical reader and the in-reader menu. |
| `App/UITests` | XCUITest UI tests. Launch with `-uiTesting` for in-memory state. |

## Rules of the road

- **UI never talks to Kavita or Suwayomi directly.** It calls `MangaServer`
  through `AppModel.client(for:)`. New backend capabilities go on the protocol
  first, with an implementation and tests for both clients.
- **All persisted changes go through `AppModel.update { }`**, which mutates
  `AppState` and saves it. Add new persisted fields to `AppState` /
  `ProfileData` with tests in `AppStateTests`.
- **Secrets never go in `AppState`.** Credentials are per profile, per server,
  in the Keychain.
- **tvOS storage is small.** Only UserDefaults (~1 MB) and the Keychain
  persist. Caches may be purged at any time. Keep `AppState` compact.
- **Profiles.** On a multi-user Apple TV the Apple TV user *is* the
  profile (see "Apple TV users" below); in-app profiles are the fallback.
  Favorites, local progress and reader settings belong to a
  profile. Kavita progress syncs to that profile's Kavita user. Suwayomi has
  one progress per server, so by default only the profile that added the
  server syncs there and others keep progress locally
  (`ProfileServerSettings.syncProgressToServer`).

## Choosing libraries to import

Each profile picks which Kavita libraries or Suwayomi categories it imports
from each server (`ProfileServerSettings.selectedCategoryIDs`, nil = all,
which is also what servers saved before this setting get). The server
editor shows the checklist once a connection test succeeds, and right away
when editing; the Library tab's "Choose Libraries/Categories" button opens
the same list (`CategorySelectionView`). `CategorySelection` holds the
rules: everything ticked is stored as nil so libraries added to the server
later show up too, and at least one must be ticked.

`AppModel.client(for:)` builds clients limited to the selection
(`MangaServerFactory.make(categoryScope:)`), so Home, Library, Search and
the server's categories all follow it. Favorites are filtered with
`AppState.visibleFavorites`, using the library/categories stored on each
`SeriesSummary` (favorites saved without them always show).

- Kavita: newly added sends a FilterV2 `Libraries contains 1,2` statement;
  On Deck passes `libraryId` when one library is picked and otherwise
  over-fetches and filters; recently updated and search have no library
  filter, so results are filtered by `libraryId`.
- Suwayomi: manga queries add `filter: {categoryId: {in: [...]}}`, and
  Default (id 0) is matched with `{categoryId: {isNull: true}}`. Chapter
  feeds first fetch the ids of manga in the picked categories and pass
  `mangaId: {in: $ids}`. Every manga query also fetches
  `categories { nodes { id } }`, and an empty list means Default.

Every client also drops anything outside the selection after the server
answers, as a safety net.

## Server API notes (verified against Kavita 0.9.1 and Suwayomi 2.4)

Kavita
- Login: `POST api/Plugin/authenticate?apiKey=…&pluginName=…` → `{ token }`, used as `Authorization: Bearer`.
- Images take `?apiKey=` and need no Bearer header: `api/Reader/image`, `api/Image/series-cover`.
- `api/Reader/file-dimensions?chapterId=` gives every page's width/height up front, so spreads are known before loading.
- List endpoints return a `Pagination` response header.

Suwayomi
- No auth by default. `orderBy`/`orderByType` work (deprecated in favor of `order: [{by, byType}]`).
- Timestamps are strings: `lastReadAt` / `fetchedAt` in seconds, `uploadDate` in milliseconds.
- `pageCount` is `-1` until `fetchChapterPages` runs. Page sizes are only known after an image downloads.
- `UpdateChapterPatchInput` fields: `isBookmarked`, `isRead`, `lastPageRead`.

## Double-page spreads

`SpreadLayout` pairs pages. Wide images are always alone; pairing restarts
after one. The first page is alone by default (cover). `shiftPairing` flips the
parity of the first run when a chapter's pairs come out wrong. Unknown sizes
count as tall; the reader re-lays out when sizes arrive and keeps the current
page on screen. See `SpreadLayoutTests` for the exact rules.

## Reader contract

`ReaderView(series:chapters:start:)` creates a `ReaderSession` and shows
`PagedReaderView` or `WebtoonReaderView` by `settings.mode`, with
`ReaderMenu` overlaid while `session.isMenuPresented` is true.

- Paged reader: `session.turn(.left/.right)` for remote presses. The first
  press past a chapter edge shows a transition card (`session.edge`), the
  second opens the next or previous chapter.
- Webtoon reader: `session.reportVisiblePage(_:)` as it scrolls.
- Both: `session.reportSize(_:forPage:)` when an image's pixel size is known.
- Menu: `session.updateSettings(_:)` applies live and saves for the series.
- Progress goes through `AppModel.recordProgress`, two seconds after the
  last page turn, on chapter change, and on close.

## Images

Every cover and page goes through `ImagePipeline.shared` (the SwiftUI
environment's `\.imagePipeline`). Pass `targetSize` in **pixels**; a side of
0 or infinity is unconstrained, so the webtoon reader can pass only a width.
Images are decoded at that size, never upscaled, and capped at 16,384 px.

- Memory: `NSCache`, 256 MB of decoded bitmaps, cleared on memory warnings.
  Target sizes are rounded up to 64 px so small layout changes reuse a decode.
- Disk: encoded bytes in `Caches/ImagePipeline`, 512 MB, oldest-first trim,
  SHA-256 file names. Only bytes ImageIO can read are stored.
- Cache keys drop Kavita's `apiKey`, so keys never reach disk and profiles share entries.
- Requests for the same URL share one download, which is cancelled only when
  every waiter is gone. At most 6 downloads run at once, and on-screen `load`s
  go ahead of prefetches.
- `prefetch(_:server:targetSize:onPixelSize:)` reports each image's original
  size, which is how readers learn Suwayomi page sizes. Without a
  `targetSize` it only downloads and reads the header.

## Paged reader

`Reader/Paged/PagedReaderView` shows one spread at a time. Frames come from
`SpreadGeometry` (both pages at one height, edge to edge, pixel-snapped) and
each image is drawn to exactly its frame, so a printed spread split across
two files reads as one picture. Pages load through the shared
`ImagePipeline` (`\.imagePipeline`), decoded to fit the screen in pixels;
the reader prefetches ±2 spreads nearest first at that same target, so
preloaded pages are memory-cache hits, and cancels prefetches that leave the
window. Sizes learned while preloading feed `reportSize`, so Suwayomi
chapters pair correctly before the reader reaches a wide page.

## Reader demo for UI tests

Launch with `-uiTesting -readerDemo` to open `ReaderView` on a local fake
series (`Reader/Demo/ReaderDemo.swift`): three chapters, one with sizes known
up front, one with sizes learned on load, pages drawn on device. Options:
`-readerDirection leftToRight`, `-readerLayout single`,
`-readerStartChapter 2`, `-readerStartPage 3`. The webtoon reader and menu
tests can reuse it. The demo injects an `ImagePipeline` whose transport
draws `demo://` pages, so it runs the real image path.

## Live servers in the simulator

`-uiTesting -liveServers` adds real servers from environment variables, so
nothing has to be typed on the simulator keyboard and no key goes in the
repo: `MR_KAVITA_OPDS` (a Kavita OPDS URL) and `MR_SUWAYOMI_URL` (plus
optional `MR_SUWAYOMI_USER` / `MR_SUWAYOMI_PASS`). From a UI test, pass them
through `app.launchEnvironment`; from `xcodebuild test`, prefix them with
`TEST_RUNNER_`.

ATS: the servers are plain HTTP on home hostnames, so the app sets
`NSAllowsArbitraryLoads`. Don't add `NSAllowsLocalNetworking`: when it is
present ATS ignores `NSAllowsArbitraryLoads` and only exempts `.local`
names and IP addresses, which blocked hosts like `kavita.home`.

## Webtoon reader

`Reader/Webtoon/WebtoonReaderView` is a continuous vertical strip. The
layout math lives in MangaCore (`WebtoonLayout`, tested in
`WebtoonLayoutTests`) and works in whole device pixels: the column width
keeps the screen's parity so it centers exactly, and each page's height is
`round(column × height / width)`, so every page starts on the pixel where
the previous one ends. Unknown sizes use the chapter's median aspect until
the image arrives.

- **No jumps.** Every re-layout (a size arrives, a chapter joins or is
  dropped, the width changes) captures a `WebtoonAnchor` (the item at the top
  of the screen and the offset into it) and restores it afterwards.
  Sizes for pages a few screens ahead are fetched early so they are right
  before they come into view.
- **Big pages.** `WebtoonTilePlan` decodes at the column width (never above
  the source size) and splits strips taller than 4096 decoded rows into
  tiles that each map to whole display pixels, within a 48 MB budget per
  page.
- **Chapters.** `WebtoonStrip` holds up to three chapters. The next chapter
  joins below when the reader is two screens from the end, the previous one
  above when scrolling near the top, with a divider between them. Crossing
  into another chapter calls `ReaderSession.adopt(chapter:pages:sizes:page:)`
  so the session switches without a loading state.
- **Remote.** `WebtoonScrollView` (UIKit, focusable; its own scrolling is off so tvOS does not add a half-screen jump per click) follows touch-surface
  swipes; click up/down glides `webtoonScrollStep` of a screen; holding
  scrolls continuously and speeds up; left/right snaps to the previous/next
  page; select opens the menu; Play/Pause toggles auto-scroll; Menu passes
  through to `ReaderView`.
- **Auto-scroll.** `WebtoonScrollDriver` moves the strip at
  `WebtoonAutoScroll.speed(level:viewport:)` (ten levels, fractions of a
  screen per second), tracking the position below a pixel so slow speeds
  stay smooth. While it runs a click stops it and up/down (clicks or
  swipes) change the level. It stops when the menu opens, a chapter loads
  or the series ends, and waits at the bottom while the next chapter
  joins. The level is saved per profile (`ProfileData.autoScrollLevel`),
  not per series, and the menu has a speed row and a Start button. The
  screen's idle timer is off while it runs.
- Only views within a screen above and two below the top exist; the rest are
  recycled.

UI tests: `WebtoonReaderUITests`, launched with
`-uiTesting -readerDemo -readerMode webtoon` (optionally
`-readerWebtoonWidth 1.0`).

## Game controllers

`Shared/Controller/GameControllerHub` watches connected extended gamepads
and passes the buttons tvOS doesn't map to the open reader (`ReaderView`
registers its session). The d-pad, A and B already drive the focus engine
like the remote's arrows, select and Menu, so browsing needs nothing
extra. The mapping lives in MangaCore (`GamepadMapping`, `GamepadStick`,
tested in `ReaderInputTests`):

| Input | Paged | Vertical |
| --- | --- | --- |
| L1 / R1 (LB / RB) | Page toward the left / right | Previous / next page |
| L2 / R2 (LT / RT) | Previous / next chapter | Previous / next chapter |
| Either stick | (focus) | Smooth scroll, quadratic past a 15% dead zone |
| X | | Toggle auto-scroll |
| Y or Options | Open / close menu | Open / close menu |
| B | Close menu, then the reader | Close menu, then the reader |

The strip ignores arrow presses while a stick is pushed in case tvOS also
turns the stick into presses, and drops a second auto-scroll toggle within
0.3 s in case one press arrives as both X and Play/Pause. XCUITest can't
press controller buttons, so only the mapping is unit tested; check on a
device with a controller.

## Reader menu

`Reader/Menu/ReaderMenu` is a drawer on the right, so the page stays in
view and changes show behind it as they're made. Swipe down or Play/Pause
(paged), a click (vertical), or Y on a controller opens it; Menu or
Play/Pause closes it. While it's open the reader under it
is disabled so focus can't leave the drawer. Two tabs:

- Settings: one row per setting, options side by side. Which rows show
  comes from `ReaderMenuOptions.items(for:)` (paged: layout, direction, and
  in two-page layout first page alone and "Shift by one"; vertical: column
  width and auto-scroll speed). Every change goes through `session.updateSettings(_:)` and is
  saved for the series. "Set as Default" copies the settings to the
  profile default; "Reset to Default" brings the series back to it.
- Chapters: the series' chapters with the open one focused; picking one
  opens it.

Control identifiers are `reader.menu.<row>.<option>` (for example
`reader.menu.layout.single`), used by `ReaderMenuUITests`.

## Apple TV users

The app has the `com.apple.developer.user-management` entitlement with
`runs-as-current-user-with-user-independent-keychain` (tvOS 16+). tvOS then
gives every Apple TV user their own copy of the app's data (UserDefaults,
the default keychain, containers), and the app is relaunched when the user
changes.

- **The Apple TV user is the profile.** Each user's `AppState` starts with
  one profile of their own, which opens at launch with no "Who's reading?"
  (`ProfileLaunch.decide`). Everything a profile owns (favorites, progress,
  reader settings, library selection, logins, and later filters and PIN)
  is therefore per Apple TV user with no extra keying: there is no user
  identifier to store, because the data itself is per user. Settings shows
  that profile for editing instead of Switch/Manage Profiles. State from
  before user management with several profiles keeps them, opening the one
  picked last (`AppState.rememberedProfileID`).
- **Servers are added once.** `SharedServerDirectory` (servers, removed
  server ids, and the login whoever added each server used) lives in the
  user-independent keychain (`KeychainSharedServerStore`,
  `kSecUseUserIndependentKeychain`). At launch `AppModel.adoptSharedServers`
  merges it into this user's state (`AppState.adopt`), and every server
  change is written back (`SharedServerDirectory.record`), so additions,
  edits and removals reach every user. Adopted servers don't sync progress
  for this user, because they'd be using someone else's login (and on
  Suwayomi, its one shared progress). `SharedFallbackSecretStore` gives a
  profile its own login when it has one, otherwise the shared one.
- **Fallback.** In the simulator, without the entitlement, or on an Apple TV
  with a single user, `TVUserManager.shouldStorePreferencesForCurrentUser`
  is false and in-app profiles work as before: one set of profiles with
  "Who's reading?" when there's more than one.
- **Other platforms.** The only platform-specific piece is
  `DeviceUserIdentity` (MangaCore). tvOS supplies `AppleTVUserIdentity`, the
  one place `TVUserManager` is used. An iPhone or Mac app would pass
  `SingleUserDevice` (in-app profiles) and reuse `AppState`, `SecretStore`
  and the server clients unchanged. Profile data is plain Codable values, so
  syncing it through iCloud/CloudKit later means syncing `ProfileData`.
- UI tests: `-appleTVUserMode` (with `-uiTestingSharedServers` and
  `-uiTestingRememberProfile <name>`), in `AppleTVUserUITests`.
