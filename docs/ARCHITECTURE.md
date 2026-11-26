# Architecture

## Layout

| Path | What lives there |
| --- | --- |
| `Packages/MangaCore` | Swift package with all non-UI logic. No SwiftUI. Tested with `swift test`. |
| `MangaCore/Models` | Shared value types: `ServerConfig`, `Profile`, `SeriesSummary`, `SeriesDetail`, `Chapter`, `PageDescriptor`, `HomeFeed`. |
| `MangaCore/Networking` | `HTTPClient`, `HTTPTransport` (mockable), and the `MangaServer` protocol every backend implements. |
| `MangaCore/Kavita` | `KavitaClient` (REST, auth key in `x-api-key`, username/password sign-in via `KavitaClient.signIn`) and `KavitaOPDS` URL parsing. |
| `MangaCore/Suwayomi` | `SuwayomiClient` (GraphQL at `/api/graphql`; no auth, basic auth, or `login` + Bearer tokens). |
| `MangaCore/Kavita` | `KavitaClient` (REST, API key → JWT via `api/Plugin/authenticate`) and `KavitaOPDS` URL parsing. |
| `MangaCore/Komga` | `KomgaClient` (REST `api/v1`/`api/v2`, API key or basic auth). |
| `MangaCore/OPDS` | `OPDSClient` (OPDS 1.2 Atom and 2.0 JSON), `OPDSParser`, `ZipArchive` and `LocalArchiveCache` for CBZ files. See `docs/SERVERS.md`. |
| `MangaCore/FreeLibrary` | `FreeLibraryClient`, the built-in source of public-domain Internet Archive items (IIIF) and Pepper&Carrot, read from the curated `catalog.json`. See [FREE_LIBRARY.md](FREE_LIBRARY.md). |
| `MangaCore/Storage` | `AppState` (profiles, servers, per-profile favorites / progress / reader settings / bookmarks), `StateStore` (UserDefaults JSON), `SecretStore` (Keychain), `ProgressSync` (queued pushes, latest-wins merge). `Bookmarks.swift`: `Bookmark`, the `BookmarkSyncing` server capability and `BookmarkSync` merge rules. |
| `MangaCore/Images` | `ImagePipeline` (`ImageLoading`): authorized image fetch, ImageIO downsampling, memory + disk cache, shared downloads, prefetch with original pixel sizes. Views use `RemoteImage` in `App/Sources/Shared/Images`. |
| `MangaCore/Sync` | iCloud sync and backup: `SyncMapper` (AppState ↔ `SyncRecord`), `SyncMerge`, `SyncEngine`, `SyncStore` (`CloudKitSyncStore`, `LocalOnlySyncStore`, `InMemoryCloudStore`), `MangaBackup`, `BackupWebServer`. See [ICLOUD.md](ICLOUD.md). |
| `MangaCore/Reader` | `ReaderSettings`, `SpreadLayout` (two-page pairing), `ReaderNavigator` (page turns, chapter edges, re-layout anchoring, preload order) and `SpreadGeometry` (seamless spread frames). |
| `App/Sources/Shared` | `AppModel`, the `@Observable` app model in the SwiftUI environment, plus shared views. |
| `App/Sources/Shared/Design` | Design tokens (`Space`, `Radius`, `Size`, `Grid`, `Layout`) and shared layout components (`SettingsPage`, `ActionRow`). Rules in `docs/DESIGN_GUIDE.md`. |
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
- **An update must never reset saved state.** New stored fields decode with
  a default when missing (`decodeIfPresent`, or an optional). Every shape a
  merged build has written is a fixture in `AppStateUpgradeTests`; when you
  change what `AppState` stores, add the JSON the build before your change
  writes. Renames or moves bump `AppState.currentVersion` with an
  `AppStateUpgrade.step`. If the normal decode still fails, `StateStore`
  salvages what it can entry by entry and keeps the original bytes under
  `StateStore.backupKey`.
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
- Auth: every call sends the profile's auth key as `x-api-key`. Older servers that refuse it get `POST api/Plugin/authenticate?apiKey=…&pluginName=…` → `{ token }` as `Authorization: Bearer`. Logging in replaces the user's only refresh token, so the app avoids it (see [PROGRESS_SYNC.md](PROGRESS_SYNC.md)).
- Username/password sign-in: `POST api/Account/login`, then reuse or `create-auth-key` "Apple TV Manga Reader". The password is never stored.
- Images take `?apiKey=` and need no Bearer header: `api/Reader/image`, `api/Image/series-cover`.
- `api/Reader/file-dimensions?chapterId=` gives every page's width/height up front, so spreads are known before loading.
- List endpoints return a `Pagination` response header.

Suwayomi
- No auth by default. `orderBy`/`orderByType` work (deprecated in favor of `order: [{by, byType}]`).
- Timestamps are strings: `lastReadAt` / `fetchedAt` in seconds, `uploadDate` in milliseconds.
- `pageCount` is `-1` until `fetchChapterPages` runs. Page sizes are only known after an image downloads.
- `UpdateChapterPatchInput` fields: `isBookmarked`, `isRead`, `lastPageRead`.
- Mark unread: `updateChapters(input: {ids, patch: {isRead: false, lastPageRead: 0}})`. A whole series looks up its chapter ids first.

Kavita mark unread: `POST api/Reader/mark-multiple-unread` with `{seriesId, volumeIds: [], chapterIds}` for chapters, `POST api/Reader/mark-unread` with `{seriesId}` for a series.

Komga (verified against 1.30.2)
- Login: `X-API-Key` header, or basic auth with the email and password. Images need it too (`authorize`).
- `POST api/v1/series/list` and `api/v1/books/list` take `{"condition": …, "fullTextSearch": …}`; `GET api/v1/series` is deprecated since 1.19.
- Pages are one-based everywhere (`books/{id}/pages/{n}`, read progress `page`). `books/{id}/pages` gives every page's width/height.
- `series/new` and `series/updated` take `library_id` as a comma-separated list. Genres come back lower-case.

OPDS (verified against Komga 1.30.2 and Stump)
- OPDS-PSE `{pageNumber}` is zero-based. `pse:lastRead` is one-based in Komga. Stump links are relative and its templates already carry a query (`?zero_based=true`).
- `URL` percent-encodes `{}`, so templates are kept as strings (`OPDSLink.template`).
- Series and chapter ids carry what's needed to reopen a book (`OPDSBook`, base64 JSON), so favorites and progress survive catalog changes. OPDS can't store progress; the editor hides the sync toggle and saves it off.

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
- Progress is saved locally on every page change
  (`AppModel.recordLocalProgress`), so a crash or force quit never loses
  the page. The server push (`AppModel.recordProgress`) waits two seconds
  after the last page turn, and also runs on chapter change, on close and
  when the app leaves the foreground.
- A chapter opened without a page resumes exactly where it was left
  (`ResumePosition`: this session's position, then local progress unless
  the server's is newer, then the server's). The previous chapter, reached
  from the start of the next one, opens on its last page; the next chapter
  opens on its first.

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
- Downloads are resilient (`RetryPolicy.images`): each attempt has a
  20 s limit, counted from when it gets a download slot so queueing never
  times out, and timeouts, dropped connections, 408/429 and 5xx are retried
  twice more after 0.75 s and 1.5 s. 401/403/404, bad image bytes and
  cancellation fail at once. Nothing about a failure is cached, so a later
  `load` (a Retry button) starts fresh. `PageLoadFailure.message(for:)`
  turns the error into a short line for the reader.
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

### Fit, zoom and crop

- **Fit** (`ReaderSettings.fit`): Fit Screen shows the whole spread; Fit
  Width fills the screen's width and Fit Height its height.
  `SpreadGeometry.canvas(for:in:_:fit:scale:)` lays the spread out on a
  canvas at least the size of the screen, with the same seamless,
  pixel-snapped frames.
- **Zoom and pan**: `PagedViewport` holds the zoom and the position as a
  0–1 fraction of what can be panned on each axis, so it survives the
  canvas changing size. Click zooms to `zoomScale` (1.5×, 2×, 3×) around
  the screen's center; click again or Menu zooms out; turning resets it.
  `PagedRemote.action(for:...)` decides what a press does: pan while more
  of the spread lies that way (forward at the end of a row drops a row and
  returns to the reading-start side), turn only at the end, and down opens
  the menu only when nothing is below. A spread reached going forward
  opens at its top, going backward at its bottom.
- **Crop borders**: `BorderCropDetector` finds plain white or black
  margins on a 256 px grayscale thumbnail and returns `CropInsets`
  (fractions). Results are cached per image URL (`PageCropCache`) and per
  page in `ReaderSession.crops`, detected for preloaded pages too, and
  before a page first shows so it doesn't jump. `SpreadCrop` keeps a
  two-page spread seamless: both pages share the smaller top and bottom
  crop and the inner edges are never cropped.
  A split wide page's half (`SpreadCrop.half`) keeps the fold uncropped
  and crops its outer side by the page's own margin.

UI tests: `ReaderFitZoomUITests` (`-readerFit width`, `-readerCrop 1`,
`-readerZoom 3`, and `-readerDemoMargins 1` to draw pages with margins).
The page indicator's accessibility value reports the viewport.

## Failed pages

A page that still fails after the automatic retries never closes the
reader or blocks page turns. It shows a card ("Page 3 didn't load", the
reason from `PageLoadFailure`, a Retry pill drawn as the focused control).
The reader keeps focus, so left/right still turn pages and Select retries
the failed pages on screen.

- Paged: `ReaderSession.pageFailures` / `retryVisibleFailedPages()`
  (Select retries before anything else Select does). Each
  page view's load task is keyed by `pageRetryTokens[page]`, so a retry
  reloads only the failed pages. Revisiting a spread retries its failed
  pages once more on its own.
- Webtoon: `WebtoonStripController.failedPages`. Failed pages are not
  reloaded on every scroll; Select retries those on screen. Size
  prefetches that fail wait 15 s before trying again.
- A chapter's page list is fetched with `RetryPolicy.pageLists` before the
  chapter error card (with Retry) shows.

## Reader demo for UI tests

Launch with `-uiTesting -readerDemo` to open `ReaderView` on a local fake
series (`Reader/Demo/ReaderDemo.swift`): three chapters, one with sizes known
up front, one with sizes learned on load, pages drawn on device. Options:
`-readerDirection leftToRight`, `-readerLayout single`,
`-readerStartChapter 2`, `-readerStartPage 3`. The webtoon reader and menu
tests can reuse it. The demo injects an `ImagePipeline` whose transport
draws `demo://` pages, so it runs the real image path.
`-readerPageFaults "1.2=fail3,2.0=hang1"` makes chosen pages (chapter
1-based, page 0-based) return HTTP 503 or hang for their first N requests
(`DemoPageFaults`), and the demo uses a short retry policy (2 attempts,
`-readerAttemptTimeout`, default 1.5 s).

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
  comes from `ReaderMenuOptions.items(for:)` (paged: layout, direction,
  in two-page layout first page alone and "Shift by one", then page fit,
  crop borders and click-to-zoom level; vertical: column width and
  auto-scroll speed). Every change goes through `session.updateSettings(_:)` and is
  saved for the series. "Set as Default" copies the settings to the
  profile default; "Reset to Default" brings the series back to it.
- Chapters: the series' chapters with the open one focused; picking one
  opens it.

Control identifiers are `reader.menu.<row>.<option>` (for example
`reader.menu.layout.single`), used by `ReaderMenuUITests`.

## Picture controls, split pages and the page scrubber

- **Picture controls** (`PictureSettings`, inside `ReaderSettings.picture`):
  brightness, contrast, color (normal, grayscale, night/invert), sharpen
  and upscaling. They sit in the Settings pane of the reader menu under
  "Picture" (rows from `ReaderMenuOptions.pictureItems(for:)`) and in
  Settings → Default Reader Settings. Brightness, contrast and color are
  SwiftUI view effects (`pictureAdjustments(_:)`), applied to the paged
  spread and to the webtoon strip, so they're instant in both readers.
  Sharpen (`CISharpenLuminance`) and Sharp (Lanczos) upscaling
  (`CILanczosScaleTransform`, for scans smaller than the screen) re-render
  page images in `Reader/Picture/PictureProcessor` (Core Image on Metal, off
  the main thread, cached), so they're paged-reader only.
- **Split wide pages** (`ReaderSettings.splitWidePages`, single-page paged
  layout): `SpreadLayout.singles(splitting:direction:)` turns a wide page
  into `.half(page, .right)` then `.half(page, .left)` for right-to-left
  (the other way for left-to-right). Both halves are the same page for
  progress and bookmarks; the indicator says "4 / 6 · Right half". The
  image decodes at twice the screen width and is clipped to the half. A
  re-layout keeps the half on screen (`spreadIndex(keeping:page:)`), and
  the chapter only completes on the last page's second half.
- **Page scrubber** (`Reader/Scrubber/PageScrubberView`, rules in
  `PageScrubber`): Pages in the menu header opens a thumbnail strip along
  the bottom with a progress bar, in either reader. Thumbnails run in
  screen order, so right-to-left series put page 1 on the right; left and
  right move a page, up/down jump 10 pages back/forward, click opens the
  page (`ReaderSession.jump(toPage:)`), Menu closes. It's shown through the
  menu's presentation flag (`ReaderSession.overlay == .scrubber`), so the
  reader is disabled and takes focus back the same way as for the menu.
- All of it is in `ReaderSettings`, so it saves per series and as the
  profile default, and syncs through the existing `readerDefaults` and
  `readerOverride` SyncMapper domains. `ReaderSettings` and
  `PictureSettings` decode missing or unknown fields to defaults, so
  settings from older or newer builds always load.
- UI tests: `ReaderPictureScrubberUITests` (`-readerSplitWide YES` turns on
  splitting in the demo reader).

## Sorting names

`NaturalSort` (MangaCore/Sorting) is the one place names are ordered:
series titles, chapter names, page and file names. Digit runs compare by
value ("Ch 2" < "Ch 10", "10.5" between 10 and 11, any length, full-width
and other Unicode digits), kanji numerals are read as numbers ("第二話" <
"第十話"), text uses the locale's collation ignoring case, accents and
width, and spaces/punctuation/brackets only separate runs. The
`.fileName` option also skips digit-free tags like `[Group]` or
`(Digital)` and the extension. Ties fall back to the exact characters, so
the order never depends on input order. Use `naturallySorted(by:)`; don't
sort names with `<` or `localizedStandardCompare`.

`ChapterOrdering.readingOrder` orders a server's chapters: by the server's
position when it has one (flipped if most neighbouring chapter numbers go
down, so one odd number can't flip a series), else by number, else by
natural name, with natural-name ties. Suwayomi uses it; Kavita keeps its
own sort numbers and breaks ties by natural name.

## Reading progress sync

Research and rules: [PROGRESS_SYNC.md](PROGRESS_SYNC.md). In code:

- `AppModel.recordProgress` writes local progress (with a secret-free
  `SeriesSummary` for the local Continue Reading row), queues a
  `PendingProgress` when the profile syncs, pushes, and clears the queue
  entry once the server accepts it.
- `AppModel.seriesDetail` merges the server's chapters with queued changes
  through `ProgressSync.reconcile` (latest `lastReadAt` wins per chapter)
  and pushes the local winners. `AppModel.syncPendingProgress` runs it for
  every series with a queue before Home loads.
- `SeriesDetail.continueChapter` follows Kavita's continue point: the most
  recently read unfinished chapter, else the first unread after the last
  read one.
- Profiles that don't sync to a server get `HomeSource.localContinueReading`.
- The server editor signs Kavita in with a username and password
  (`AppModel.resolveCredential`, faked in UI tests: reader / secret) and
  turns sync on for Suwayomi logins that map to a server user.
- Tests: `ProgressSyncTests`, sign-in tests in `KavitaClientTests` and
  `SuwayomiClientTests`, UI tests in `ProgressSyncUITests`.

## Library browsing and Home layout

Per-profile browsing preferences live in `ProfileData.browse`
(`BrowsePreferences`, nil until something changes, and only non-default
fields are encoded). `AppState+Browse.swift` and `AppModel+Browse.swift`
hold the accessors.

- **Sort & View** (`Library/LibraryOptionsView`, one per library or
  category, keyed by `LibraryKey`): `LibrarySort` (title A–Z/Z–A, recently
  added, updated, read), the library's `LibraryReadingStyle`, `GridOrder`,
  and the profile-wide `GridDensity` (poster size for library grids and
  Favorites; shelves keep 230 pt).
- **Sorting.** `MangaServer.series(in:page:pageSize:sort:)` (the default
  implementation ignores `sort`). Kavita sends FilterV2 `sortOptions`
  (SortName 1, CreatedDate 2, LastChapterAdded 4, ReadProgress 7). Suwayomi
  returns whole categories, so `SuwayomiClient+Sorting` asks for
  `inLibraryAt`, `chapters { totalCount }`, `latestFetchedChapter` and
  `lastReadChapter`, sorts on the client, and keeps page 1's answer for
  five minutes so later pages don't download the category again. If the
  server rejects those fields it falls back to the basic ones.
- **A–Z jump.** `AlphabetIndex` maps titles to `#`/A–Z (accents and
  full-width letters folded, CJK under `#`) and finds the first title at or
  past a letter; `.needsMore` means the grid loads the next page and tries
  again. `AlphabetJumpBar` sits beside title-sorted grids; picking a letter
  scrolls to the poster and focuses it.
- **Reading direction by library.** `AppState.readerSettings(for: SeriesSummary)`:
  the series' own settings, else the profile default with the first of its
  libraries/categories' styles applied. The reader menu's "Reset to Default"
  goes back to that.
- **Right-to-left grids.** `SeriesGrid(rightToLeft:)` flips the grid's layout
  direction (posters keep left-to-right text). `GridOrder.automatic` is right
  to left only when the library's style is Right to Left.
- **Poster badges.** `PosterBadges(series:)`: Kavita gets a page progress
  bar and "N pages" (its `unreadCount` is pages, too big for a badge);
  Suwayomi grids get unread chapters, a progress bar and "N chapters"; a
  check when finished. Unread chapters in series detail show their page count.
- **Home.** `HomeLayout` orders `HomeRowKind`s and hides some (Settings →
  Customize Home, or the button at the bottom of Home). Server feeds
  (Continue Reading, Recently Updated, Newly Added) are merged into one row
  each across servers by default (`HomeLayout.serverRows == .merged`):
  `HomeMerge` interleaves each server's list without reordering it, newest
  `SeriesSummary.feedDate` first (last read / added / new chapter, set by
  the Kavita, Suwayomi, Komga and Free Library feeds), else by rank on its
  server. "Row per Server" brings back "Recently Updated · Server" rows.
  `HomeLoader.each` streams each server's section as it arrives, so Home
  shows fast servers without waiting for the slowest. Rows come from
  `model.client(for:)`, so library selection and content filters apply.
  Posters in rows that mix servers name their server
  (`HomeLayout.serverLabel`: on the caption's line, a tag on the cover, or
  off; the poster's VoiceOver label always says it). UI-test flags:
  `-homePerServer`, `-posterServerLabel onCover|off`. Shelf ids: merged
  `shelf.<feed>`, per server `shelf.<server>.<feed>`.
- **Series location.** Series detail shows "server · library" under the meta
  line (`SeriesPlacement`): Kavita's `libraryName`, Komga's library, every
  Suwayomi category (Default when none) plus its source, the Free Library
  collection; otherwise (OPDS, demo) the summary's library/category ids
  looked up in `categories()` (`MangaServer.placement(for:detail:)`).
  Long-press a Continue Reading poster to remove it; it comes back once the
  profile reads it again (`dismissedContinueReading` vs local progress).
- **Caught Up.** Series detail calls `AppModel.noteSeriesDetail`: a series
  with every chapter read joins the row (newest first, at most 30), and
  leaves it when detail shows an unread chapter or a Home feed lists it with
  unread chapters.
- **Search** strips the period, question mark and quotes Siri dictation adds.
- **Audio.** `AudioSessionSetup` sets the ambient category at launch so the
  user's music keeps playing.

UI tests: `LibraryBrowsingUITests` (`-uiTesting -demoServers`; add
`-demoFinished 1` to mark Demo Kavita's series 1 read).

## Books and PDFs

See [BOOKS-AND-PDF.md](BOOKS-AND-PDF.md) for what each backend serves.

- `ContentFormat` (`images`, `pdf`, `epub`, `text`) is on `SeriesSummary`
  and `Chapter` (nil means images). Kavita maps its `MangaFormat`. Posters
  and chapter rows show a `FormatBadge` for PDF/EPUB/TXT only.
- PDFs read in the image readers: Kavita renders their pages
  (`extractPdf=true`).
- `ReaderView` hands chapters whose format `isText` to
  `Reader/Book/BookReaderView`. The backend must conform to `BookProviding`
  (`bookManifest(for:)`, `bookSection(_:of:)`); `KavitaClient` does, through
  `api/Book/{chapterId}/book-info`, `/chapters` and `/book-page`.
- `HTMLBookParser` / `PlainTextBookParser` (MangaCore/Book) turn a section
  into `BookBlock`s. `BookLayoutEngine` builds attributed text and
  paginates it with TextKit into one or two columns; `BookSectionLayout`
  draws a page with the same layout manager. `BookCursor` (MangaCore, tested)
  moves across pages and sections.
- Settings (`BookSettings`) are per profile in `ProfileData.bookSettings`.
  Progress: the section index goes to the server as the page; the place
  inside the section is kept in `AppModel.bookPositions`.
- UI tests: `BookReaderUITests` with `-uiTesting -readerDemo -readerBook`
  (public-domain Alice in Wonderland, `Reader/Demo/DemoBook.swift`).
  Identifiers: `book.page` (value `<section>.<page>`), `book.position`,
  `book.edge`, `book.menu.<row>.<option>`, `book.toc.<n>`.

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

## Bookmarks

A `Bookmark` is one page of one chapter, stored per profile in
`ProfileData.bookmarks` with the series summary so it can be listed without
the server. UI: in the reader, the menu's "Bookmark This Page" button (both
modes) or a press up in the paged reader toggles the page on screen, with a
ribbon in the corner while a bookmarked page shows; the menu's Bookmarks tab
jumps to one. Series detail lists the series' bookmarks above the chapters,
and the Bookmarks tab lists every bookmark grouped by series. Holding select
on a bookmark offers Remove.

Sync goes through `BookmarkSyncing`, a capability protocol beside
`MangaServer` (`AppModel.bookmarkClient(for:)` casts to it), and only for
profiles that sync progress to that server:

- Kavita (`.page`): `GET api/Reader/series-bookmarks`, `POST
  api/Reader/all-bookmarks` (FilterV2 body), `POST api/Reader/bookmark` and
  `unbookmark` with `{page, volumeId, seriesId, chapterId}`. The Kavita user
  needs the Bookmark role; failures leave the bookmark local.
- Suwayomi (`.chapter`): `isBookmarked` on chapters. A page bookmark
  bookmarks its chapter; the chapter is unbookmarked when its last page
  bookmark goes. A chapter bookmarked elsewhere (Mihon) shows as page 1.

New bookmarks start with `needsUpload` and are cleared once the server
confirms. `BookmarkSync.merge` treats the server as the truth for confirmed
bookmarks (gone from the server means removed elsewhere) and keeps pending
ones, which the next sync uploads. Series detail merges that series on load;
the Bookmarks tab merges whole servers. A removal that fails to reach the
server comes back on the next merge.

## Favorites sorting

`FavoritesSort` (key + direction) is saved per profile in
`ProfileData.favoritesSort`. Keys: date favorited, title, latest chapter
("Updated"), last read (local progress time), unread chapters, server.
Picking the selected key again, or the direction button, flips the order.
Missing values sort last either way; ties go by title.

"Updated" and "Unread" need server data, kept on `Favorite`
(`latestChapterAt`, `unreadChapters`, `refreshedAt`). They refresh whenever
series detail loads (`AppModel.didLoadSeriesDetail`) and, when the Favorites
tab opens, for favorites not refreshed in the last hour (four at a time).
`SeriesDetail.latestChapterDate` is Kavita's `lastChapterAdded` when present,
else the newest chapter date.

UI tests: `-uiTesting -demoServers -demoFavorites` seeds four favorites with
distinct sort values and two bookmarks (`AppModel+DemoBookmarks.swift`), used
by `FavoritesSortUITests` and `BookmarksUITests`.

## Mark as unread

Long-pressing a chapter row offers "Mark as Unread" and "Mark Series as
Unread"; the series "More" button and a poster's long-press offer "Mark
Series as Unread". `AppModel.markUnread` / `markSeriesUnread` always update
the profile's local progress and call the server only when the profile
syncs there. Locally, `SeriesProgress.unreadChapterIDs` hides the server's
read state for those chapters until they are opened again, and
`ignoresServerProgress` (set by a series reset) makes only local progress
count, so a profile that doesn't sync to Suwayomi can still reset a
series. Series detail updates immediately (`SeriesDetail.markingUnread`)
and reloads after the server answers; poster badges use
`AppModel.unreadCount(for:)`. UI tests: `MarkUnreadUITests`, launched with
`-demoProgress` so demo series start with progress.

## Screen titles and scrolling headers

tvOS keeps a `.navigationTitle` pinned while a Form or List scrolls, so the
title ends up drawn over the rows. Settings screens use `.settingsPage(...)`
(docs/DESIGN_GUIDE.md), which puts the title in a side column; any other
screen puts its title inside its scrolling content. Panels with their own
header (the in-reader menu) keep the header inside the same ScrollView as
the rows. `.scrollClipDisabled()` is for horizontal shelves and tab bars: on
a vertical scroll view it lets rows slide over whatever sits above it.
`tools/check_pinned_headers.py` enforces both rules in CI (a reviewed
exception ends its line with `// pinned-header-ok: <reason>`), and
`ReaderMenuUITests.testHeaderScrollsWithOptions` scrolls the menu down and
back up.

## Top Shelf

`MangaReaderTopShelf` (a `tv-app-extension` target, sources in `TopShelf/`)
shows two sections for the active profile: Continue Reading (local progress,
newest first) and Favorites (favorites with new chapters first, labelled
"· N new"; series already in Continue Reading aren't repeated).

- The app does all the work. `TopShelfPublisher` (App/Sources/TopShelf)
  watches `AppModel.stateObservers`, rebuilds `TopShelfSnapshot.make(from:)`
  a few seconds after a change (so after progress saves), writes
  `snapshot.json` and JPEG covers (800×1200 px) to the App Group
  `group.com.rustedimac.MangaReader` (`TopShelfStore`), and calls
  `TVTopShelfContentProvider.topShelfContentDidChange()`.
- The extension only decodes that file and points at the cover files, so it
  stays well inside its memory limit and never talks to a server. Cover file
  names are SHA-256 hashes of the URL without `apiKey`, so no keys reach disk.
- Titles and covers for Continue Reading come from
  `ProfileData.recentSeries`, noted when the reader opens a series.
  Favorites' new-chapter counts are `Favorite.unreadChapters` (see Favorites
  sorting), refreshed by `refreshStaleFavorites()` when the app becomes
  active and when the Favorites tab opens.
- Items link back with `DeepLink` (`mangareader://series?…` for select,
  `mangareader://read?…&chapter=…&page=…` for Play). `RootView.onOpenURL`
  switches to the link's profile, closes "Who's reading?", and presents
  `DeepLinkView` over the tabs.
- Without the App Group (unsigned CI simulator builds) and in UI tests the
  publisher is off. Per Apple TV user, the App Group is per user too, so each
  user's Top Shelf shows their own profile.
- UI tests: `TopShelfLinkUITests` with
  `-uiTestingOpenLink series:<server>:<id>` or `read:<server>:<id>:<chapter>`.
