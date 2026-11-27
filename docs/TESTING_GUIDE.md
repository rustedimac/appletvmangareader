# Testing guide

One repeatable test pass for the app, with a pass/fail rule for every check.
Run it before a release, after a large merge, or whenever someone asks "does
it all still work?". Every feature PR keeps it current (see
[Keeping this guide current](#keeping-this-guide-current)).

Related pages: [CI.md](CI.md) (where automated tests run),
[DESIGN_GUIDE.md](DESIGN_GUIDE.md) (layout rules the design checks enforce),
[READER_CONTROLS.md](READER_CONTROLS.md) (what each button should do),
[UPGRADE_SAFETY.md](UPGRADE_SAFETY.md) (saved data rules),
[APPLE_TV_TESTING.md](APPLE_TV_TESTING.md) (installing on a real Apple TV).

## 1. Levels

A test pass runs the levels in order and stops to fix (or file) anything at
severity S1 before going on.

| Level | What | Where | Time | Command or how |
| --- | --- | --- | --- | --- |
| L0 | Lint | Linux or Mac | seconds | every `tools/check_*.py` (the `ui-lint` CI job), including `check_testing_guide.py` |
| L1 | MangaCore unit tests | Mac or CI | ~1 min | `cd Packages/MangaCore && swift test` |
| L2 | UI smoke set | CI on every PR | ~20 min | `tools/ui_smoke_tests.txt` |
| L3 | Full UI suite | CI on main/nightly, or the maintainer's Mac | ~20 min Mac, ~55 min CI | see [Running L3 on the Mac](#running-l3-on-the-mac) |
| L4 | Live servers in the simulator | maintainer's Mac, home network | ~30 min | the rows marked **S** below, by hand with the app the maintainer already set up |
| L5 | Real Apple TV | living room | ~45 min | the rows marked **D** below |

L0 to L3 use only fictional demo data (`-uiTesting`, `-readerDemo`, mock
transports, the fixtures). L4 and L5 use real servers, so their notes stay
out of the repository (see section 5).

### Running L3 on the Mac

Use the separate UI-test simulator, never the one that holds the maintainer's
servers and profiles. UI tests reset app data on launch.

```
xcodegen generate
xcodebuild test -project MangaReader.xcodeproj -scheme MangaReader \
  -destination 'platform=tvOS Simulator,id=<UI-test simulator id>' \
  -resultBundlePath build/l3.xcresult CODE_SIGNING_ALLOWED=NO
```

Report only failing tests with their assertion lines
(`xcrun xcresulttool get test-results tests --path build/l3.xcresult`).

## 2. Pass, fail and severity

Every check below has a **Pass when** column. A check:

- **Passes** when everything in that column is true, on the first try.
- **Fails** when any part is false, or it passes only on a retry (note
  "flaky" and treat it as a fail at one severity lower).
- Is **Blocked** when it can't be run (no server, no device, a failure
  earlier in the same flow). Say what blocked it.
- Is **N/A** only when the build doesn't have the feature yet.

| Severity | Meaning | Release |
| --- | --- | --- |
| S1 | Crash, hang, data loss (progress, servers, favorites, bookmarks, settings), can't open or read a chapter, a secret shown or logged, a hidden/PIN-locked item reachable | Blocks |
| S2 | A feature doesn't work, or works only one way (e.g. RTL but not LTR), wrong page shown, focus stuck, progress not synced | Blocks unless John waives it |
| S3 | Cosmetic, a wording issue, a design-guide rule broken, slow but usable | Doesn't block; file it |

**Release ready** means: L0 to L3 all green on the release commit, no S1 or
S2 open from L4 and L5, and every L5 row run on the device at least once
since the last change to the area it covers.

## 3. Checks

Columns: **ID** is stable (never reuse a removed ID). **Lvl**: **A** =
automated (the test named in *Covered by* runs it), **S** = by hand in the
simulator against live servers, **D** = only on a real Apple TV. An **A** row
may also say *also S* when the automated test uses demo data and the live
server behaviour is worth a look.

### 3.1 Launch, first run, profiles

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| LCH-01 | A | Launch the app | Tab bar shows Home, Library, Search, Favorites, Settings; no crash | `SmokeUITests`, `TabBarVisibilityUITests` |
| LCH-02 | A | Empty install | Welcome offers Free Library collections, Add a server, Restore a backup; picking collections lands on Home with them; removing every source brings Welcome back | `WelcomeUITests`, `WelcomeTests` |
| LCH-03 | A | Install with servers | Welcome never shows | `WelcomeUITests` |
| PRF-01 | A | One profile | Opens straight to Home, no picker | `ProfilesUITests` |
| PRF-02 | A | Two or more profiles | "Who's reading?" picker shows, centered; add, switch and delete work | `ProfilesUITests`, `AppStateTests` |
| PRF-03 | A | Apple TV users | Each Apple TV user opens straight into their own profile; servers added by one user show for another with that user's login | `AppleTVUserUITests`, `AppleTVUserTests` |
| PRF-04 | A | Guest session | Starts empty, saves and syncs nothing; ending it brings back the owner's favorites and progress unchanged | `GuestUITests`, `GuestSessionTests` |
| PRF-05 | A | Profile PIN and content filters | PIN asked before a locked profile opens and before content settings; a hidden genre disappears from Home, Library, Search and Top Shelf links | `ContentFilterUITests`, `ContentFilterTests`, `ProfilePINTests`, `TopShelfLinkUITests` |
| PRF-06 | S | Second profile against Kavita | Shows "<name> isn't signed in to Kavita" until that profile has a login; Suwayomi works without one; Favorites and Continue Reading differ between profiles | manual |

### 3.2 Servers and sources

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| SRV-01 | A | Add server types | Add Server offers Kavita, Suwayomi, Komga, OPDS; never Free Library | `ServersUITests`, `KomgaUITests`, `OPDSUITests`, `FreeLibraryUITests` |
| SRV-02 | A | Pasted Kavita OPDS URL | Field keeps the paste while typing; on Return/Test/Save it splits into address and key (dots) | `ServersUITests`, `ServerDraftTests`, `CredentialSaveTests` |
| SRV-03 | A | Edit and remove a server | Changes apply; removing it removes its rows from Home without a relaunch | `ServersUITests`, `ContentRefreshUITests` |
| SRV-04 | A | Several addresses per server | Editor shows every address; Add Another Address adds a field; a dead first address falls back to the next | `ServerAddressesUITests`, `ServerAddressTests`, `HTTPClientTests` |
| SRV-05 | A | Phone setup by QR | QR and address show; a phone form submission fills the editor | `ServerAddressesUITests`, `PhoneSetupTests` |
| SRV-06 | A | Pick libraries/categories | Editor lists them; ticks save without Save; nothing ticked can't be saved; unticked ones leave Home and Library | `CategorySelectionUITests`, `CategorySelectionTests`, `CategoryScopeClientTests` |
| SRV-07 | A | Kavita username/password sign-in | Right password signs in; wrong one says so | `ProgressSyncUITests`, `KavitaClientTests` |
| SRV-08 | A | Komga and OPDS | Komga signs in and shows rows; OPDS editor finds the catalog from a bare host; series open | `KomgaUITests`, `KomgaClientTests`, `OPDSUITests`, `OPDSTests`; live: `KomgaLiveTests`, `OPDSLiveTests` (skip without `KOMGA_LIVE_URL` / `OPDS_LIVE_URL`) |
| SRV-09 | A | Free Library | Home shows it with no setup; series show the credit and open the reader; Settings can remove and restore it | `FreeLibraryUITests`, `FreeLibraryTests` |
| SRV-10 | S | Live Kavita and Suwayomi | Test Connection shows a green check; a wrong host says "Couldn't reach", a wrong key says "rejected the API key"; both servers' rows load on Home within a few seconds | manual |
| SRV-11 | A | Client parsing | Kavita, Suwayomi, Komga, OPDS responses (fixtures) map to series, chapters and pages; natural sort for "Ch 2" before "Ch 10", brackets and CJK names | `KavitaClientTests`, `KavitaBookTests`, `SuwayomiClientTests`, `KomgaClientTests`, `OPDSTests`, `NaturalSortTests`, `SortingClientTests`, `SeriesPlacementClientTests` |

### 3.3 Home, Library, Search, Favorites

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| HOM-01 | A | Home rows | Favorites, Continue Reading, Recently Updated, Newly Added; merged into one row per feed by default, a row per server as an option; server name on covers toggles | `BrowseUITests`, `HomeServerRowsUITests`, `HomeMergeTests` |
| HOM-02 | A | Customize Home | Rows hide and reorder; Remove from Continue Reading works; Customize Home is reachable with Down from any poster in the last row | `LibraryBrowsingUITests` |
| HOM-03 | A | Changes show without a relaunch | New server, unticked library, poster size change update Home at once | `ContentRefreshUITests` |
| HOM-04 | A | Caught Up shelf | Finished series show there | `LibraryBrowsingUITests` |
| HOM-05 | A | Theme change keeps Home | After switching theme (to a theme and back to Default), every server's rows are still on Home at once, not only Free Library while the servers load again | `HomeThemeSwitchUITests`, `HomeSnapshotTests` |
| LIB-01 | A | Library grid | Categories as tabs, pages load as you scroll; jump bar loads later pages and focuses the letter | `BrowseUITests`, `LibraryBrowsingUITests`, `BrowseTests` |
| LIB-02 | A | Sort, filter, defaults | Title A-Z/Z-A, recently added; status/read/genre filters; Library Defaults apply to every library | `LibraryBrowsingUITests`, `LibraryFilterTests`, `LibraryBrowsingTests` |
| LIB-03 | A | Posters | Title moves clear of the focused cover; long titles wrap to two lines; captions (chapters, pages, progress bar, %, off) line up across a row; progress updates after reading | `PosterLayoutUITests`, `LibraryBrowsingUITests`, `ProgressPercentTests` |
| LIB-04 | A | Right-to-left library | RTL grid order and reading direction come from the library default | `LibraryBrowsingUITests` |
| LIB-05 | A | Kavita reading lists, collections, smart filters | Each lists its items; a reading list opens chapters in order | `ServerCollectionsUITests`, `KavitaCollectionsTests` |
| LIB-06 | S | Big live category | A 700+ series Suwayomi category keeps loading while scrolling, no stall over 2 s | manual |
| SRC-01 | A | Search | Results group by server; dictation hint shows; hidden genres excluded | `BrowseUITests`, `LibraryBrowsingUITests`, `ContentFilterUITests` |
| FAV-01 | A | Favorites | Favorite from the series page shows on Home and the Favorites tab; sorts (newest first by default) and direction survive a tab switch | `BrowseUITests`, `FavoritesSortUITests`, `FavoritesSortTests` |
| NAV-01 | A | Coming back after a while | Home and Settings return to the top level after being away; a quick back keeps the sub-screen | `NavigationResetUITests` |

### 3.4 Series page

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| SER-01 | A | Series detail | Synopsis, genres, server and libraries, chapter list with read state; Start/Continue opens the reader | `BrowseUITests`, `HomeServerRowsUITests` |
| SER-02 | A | Mark read/unread | Chapter and series, from long press, the "…" button and More; marking previous chapters read works | `MarkUnreadUITests`, `MarkReadTests`, `MarkUnreadTests` |
| SER-03 | A | Bookmarks | Series page lists bookmarks; one in another chapter opens that chapter at the page | `BookmarksUITests`, `BookmarkTests` |

### 3.5 Paged reader

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| PGR-01 | A | Right-to-left | Forward goes left; pairs read right then left; turns through the chapter into the next via a card that can be backed out of | `PagedReaderUITests`, `ReaderNavigatorTests` |
| PGR-02 | A | Previous chapter | Going back from page 1 opens the previous chapter on its **last** spread | `PagedReaderUITests`, `ResumePositionTests` |
| PGR-03 | A | Left-to-right and single page | LTR turns the right way; single layout hides pairing options | `PagedReaderUITests`, `ReaderMenuUITests` |
| PGR-04 | A | Spreads | Two halves of a spread join with no gap; a wide page shows alone; sizes learned while reading fix pairing; First Page Alone repairs pairs both ways and stays on the same page | `PagedReaderUITests`, `ReaderMenuUITests`, `SpreadLayoutTests`, `PagePairingTests` |
| PGR-05 | A | Fit, zoom, crop | Fit width fills the width and scrolls a tall page before turning; click zooms, Menu zooms out; a zoomed page turns at the edge without skipping a row; crop trims margins and keeps spreads seamless; crop turns off | `ReaderFitZoomUITests`, `PagedViewportTests`, `BorderCropTests` |
| PGR-06 | A | Split wide pages | In single layout a wide page splits into halves in reading order (RTL aware) | `ReaderPictureScrubberUITests`, `PictureAndSplitTests` |
| PGR-07 | A | Page load failures | One failed request retries by itself; a hanging one times out and retries; Select retries in place; a failed half of a spread doesn't stop the other or page turns | `PagedPageRetryUITests`, `RetryPolicyTests`, `ImagePipelineTests` |
| PGR-08 | S | Live spread chapter | A Kavita chapter with a two-page color spread lines up with no line at the spine; pairs right after a cover | manual |
| PGR-09 | D | Feel and sharpness | Page turns instant after preload; text sharp on a 4K TV | manual |
| PDF-01 | A | PDFs | Open in the paged reader with page count and progress | `KavitaBookTests`, `PagedReaderUITests` |

### 3.6 Vertical (webtoon) reader

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| WTN-01 | A | Seamless column | Pages join with no gap in a centered column; a wide page joins its neighbours; full width setting works | `WebtoonReaderUITests`, `WebtoonLayoutTests` |
| WTN-02 | A | Scrolling | Click scrolls one step, hold scrolls continuously; click right snaps to the next page | `WebtoonReaderUITests`, `ReaderInputTests` |
| WTN-03 | A | Chapter end | Scrolling past the end joins the next chapter seamlessly; end-of-series footer shows | `WebtoonReaderUITests` |
| WTN-04 | A | Resume and memory | Resume stays put while unknown page sizes arrive; far pages are recycled | `WebtoonReaderUITests`, `ImageCachingTests` |
| WTN-05 | A | Auto-scroll | Play/Pause starts it; up/down change the speed while it runs; the menu shows and changes the speed | `WebtoonAutoScrollUITests` |
| WTN-06 | A | Page load failures | Same as PGR-07; a page that never loads doesn't block reading past it | `WebtoonPageRetryUITests` |
| WTN-07 | S | Live webtoon | A Suwayomi webtoon chapter: no seams while pages load, divider into the next chapter | manual |
| WTN-08 | D | Long chapter | 100+ pages stays smooth, no memory warning or crash after 5 minutes; swipe scrolling feels smooth | manual |

### 3.7 Book reader (EPUB, text)

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| BOK-01 | A | Turning pages | Forward and back; crosses sections and chapters | `BookReaderUITests`, `BookCursorTests`, `HTMLBookParserTests` |
| BOK-02 | A | Settings and contents | Settings apply live; Contents jumps to an entry; place in the book is kept | `BookReaderUITests`, `BookSettingsTests` |

### 3.8 Reader options, controls, picture

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| MNU-01 | A | Opening the options | Opens on the current mode's rows with the page visible; the route named in READER_CONTROLS.md opens it in each reader (also while auto-scrolling); Menu and Play/Pause close it and pages still turn | `ReaderMenuUITests`, `ReaderControlsUITests`, `PagedReaderUITests` |
| MNU-02 | A | Rows and scopes | A row opens its choices, Menu goes back; every setting applies live; per series, Set as Default and Reset work | `ReaderMenuUITests`, `ReaderMenuOptionsTests`, `tools/check_setting_scopes.py` |
| MNU-03 | A | Chapters and bookmarks tabs | Chapter list jumps to a chapter and back to the exact page; bookmark from Up and from the menu; Bookmarks tab lists and opens them | `ReaderMenuUITests`, `BookmarksUITests` |
| MNU-04 | A | Picture controls | Brightness, contrast, invert, background apply and reset; vertical offers color but not sharpen | `ReaderPictureScrubberUITests`, `PictureAndSplitTests` |
| MNU-05 | A | Page scrubber | Jumps to a page; runs right to left for manga; works in the vertical reader | `ReaderPictureScrubberUITests` |
| CTL-01 | A | First-use hint and legend | Hint names the route on first opens, goes away with the options; Settings lists the button map | `ReaderControlsUITests`, `ReaderControlsTests` |
| CTL-02 | A | Game controller mapping | Each button does what READER_CONTROLS.md section 10 says | `ReaderInputTests`, `ReaderControlsTests` |
| CTL-04 | A | Controls tutorial | Offered once on the first reader open (Not Now keeps reading, Show Me runs it); each step waits for its input and other buttons don't break it; Menu leaves it; Settings > Remote and Controller replays it and shows the CC BY credit; nothing is saved | `ReaderTutorialUITests`, `ReaderTutorialTests` |
| CTL-05 | A | Back with the options open | In a full-screen cover (as the app presents the reader) and from series detail, Menu closes open choices, then the scrubber or options, and the reader stays open: Settings, Chapters and Bookmarks tabs, after Set as Default / Reset, scrolled to the Controls legend, after switching paged to vertical, while zoomed (the next Menu zooms out), with the page timer or auto-scroll running, and in the book reader. Only the Menu after that closes the reader | `ReaderBackUITests`, `ReaderControlsUITests` |
| CTL-03 | D | Real remote and controller | Siri Remote click, hold, swipe and Back behave as documented; a paired controller does too | manual |

### 3.9 Progress, sync, backup, saved data

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| SYN-01 | A | Progress sync logic | Kavita page progress and Suwayomi chapter progress are sent, queued on failure and retried; a profile that doesn't sync keeps local Continue Reading | `ProgressSyncTests`, `ProgressSyncUITests`, `RetryPolicyTests` |
| SYN-02 | S | Live progress | Read a few pages of a Kavita chapter, leave: Kavita's web UI shows the same page. Finish it: Kavita marks it read and Home updates. Same in Suwayomi for the syncing profile | manual |
| SYN-03 | S | Quit mid-chapter | Quit from the app switcher, reopen: same page | manual |
| SYN-04 | A | iCloud and Wi-Fi backup | Sync is off with an explanation without iCloud; Wi-Fi backup shows an address; sync engine, mapper and merge rules hold | `ICloudSyncUITests`, `CloudSyncAvailabilityTests`, `SyncEngineTests`, `SyncMapperTests`, `SyncMergeTests`, `SyncCoverageTests`, `BackupWebServerTests` |
| SYN-05 | A | Backup files | Export, then restore into a fresh install, brings everything back | `MangaBackupTests` |
| DAT-01 | A | Upgrade safety | Every saved-data fixture loads; missing or unknown fields lose nothing; the newest fixture covers every field | `SavedDataUpgradeTests`, `AppStateUpgradeTests`, `AppStateTests` |
| DAT-02 | S | Install over the old build | Installing the new build over the maintainer's app keeps servers, logins, profiles, progress, favorites, bookmarks | manual |

### 3.10 Top Shelf and system

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| TOP-01 | A | Top Shelf links | Series link opens the series; Read link opens the reader and Menu returns; skips Who's reading; asks a PIN where set; hidden series don't open | `TopShelfLinkUITests`, `TopShelfTests` |
| TOP-02 | D | Top Shelf and icon | Top Shelf shows continue reading with the app in the top row; icon parallax | manual |

### 3.11 Design and accessibility

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| DES-01 | A | Layout rules | Every reachable screen: targets at least 60 pt, inside the safe area, form width, no overlaps, uniform row heights, value next to chevron | `DesignLayoutUITests`, `tools/check_design_tokens.py`, `tools/check_pinned_headers.py`, `tools/check_option_chips.py`, `tools/check_save_buttons.py`, `tools/check_secure_fields.py` |
| DES-04 | A | Remote and Controller fits | Every tab: section tabs below the tab bar; legend, footnote, Learn the Controls and its caption inside the bottom safe area (tutorial tabs once the button has focus) | `DesignLayoutUITests.testControlsPageNeverClips` |
| DES-02 | A | Section tabs | Reader and book tabs look like the top bar | `ReaderMenuUITests`, `BookReaderUITests` |
| DES-03 | S | Themes | All five themes: text on every plate, focused, open and plain, passes 4.5:1 as drawn (library server list, category bar, Choose Libraries, Settings); token pairs pass in light and dark; each theme looks like its Theme Lab tvOS sample (glazed plates / ink plates, themed focus) | `ThemeScreensUITests`, `tools/check_theme_contrast.py`, manual look |
| A11Y-01 | S | Large text and Bold Text | Largest Dynamic Type and Bold Text: no clipped labels, nothing off screen | manual |
| A11Y-02 | S | VoiceOver | Tabs, posters, rows and reader pages read a sensible label; reader page says "Page N of M" | manual |

### 3.12 iPhone and iPad

Run on an iPhone and an iPad simulator (`MangaReaderiOS` scheme), and on a
real device before a release. iOS UI tests live in `App/UITests-iOS`.

| ID | Lvl | Check | Pass when | Covered by |
| --- | --- | --- | --- | --- |
| IOS-01 | A | Launch and tabs | iPhone: Home, Library, Favorites, Settings and a separate Search button, no More; iPad: all six tabs, sidebar toggle; every tab opens | iOS `SmokeUITests` |
| IOS-02 | A | Reader chrome | Opens with the top bar (Close, title, bookmark, options) and the page bar; a centre tap hides both with the status bar, again shows them; Close closes the reader | iOS `ReaderTouchUITests` |
| IOS-03 | A | Tap zones | Left and Right: side thirds turn following the reading direction; Both Sides Forward: either side goes forward; Off: side taps only toggle; vertical reader side taps scroll a step | `ReaderTouchTests`, iOS `ReaderTouchUITests` |
| IOS-04 | A | Swipe and zoom | A swipe turns (page follows the finger); pinch zooms up to 4x and pans; double-tap zooms to 2x and back; zoomed, side taps don't turn | `ReaderTouchTests`, iOS `ReaderTouchUITests` |
| IOS-05 | A | Orientation | Portrait shows single pages, landscape pairs spreads per Page Layout; rotating keeps the page | `ReaderTouchTests`, iOS `ReaderTouchUITests` |
| IOS-07 | S | Layouts | iPhone: three poster columns in a library, posters inset from the edges, series page with cover beside title and full-width Continue; iPad: more columns, regular series layout; Split View switches to the iPhone layout; Bookmarks opens from Favorites on iPhone | iOS `SmokeUITests`, manual look |
| IOS-08 | A | System pieces | Settings > iCloud Sync and Backup > Back Up and Restore exports a backup to Files and restores one (an Apple TV backup too); no "Set Up from Your Phone" in the server editor; no Remote and Controller page; light and dark follow the system with the Default theme | iOS `SystemUITests`, manual look |
| IOS-06 | S | Options | The options open as a sheet on iPhone, a popover on iPad, readable over any page, with Tap Zones; Done closes them | iOS `ReaderTouchUITests` |

## 4. A test pass, step by step

1. Note the commit (`git rev-parse --short HEAD`), the date, the Xcode and
   tvOS simulator versions.
2. L0: run every `tools/check_*.py`. L1: `swift test`.
3. L3 on the Mac (or use the last green full CI run on that commit). Write
   down the failing tests only.
4. L4: install over the maintainer's app on their simulator (`simctl
   install`, never erase), then walk the **S** rows. Don't add or change
   their servers or logins.
5. L5 when a device run is due.
6. Fill in the record (section 5). For each fail: ID, severity, what you
   saw, how to reproduce. File S1/S2 as issues or backlog items.

## 5. Recording a run

Keep run records out of the repository: they name home servers and real
series. Store them with the project's files (`test-runs/YYYY-MM-DD.md`).
Use this shape:

```
# Test pass YYYY-MM-DD, commit abc1234
Xcode x.y, tvOS simulator x.y (UI-test sim), servers: Kavita x, Suwayomi y

| Level | Result | Notes |
| L0 | pass | |
| L1 | 811/811 | |
| L3 | 205/207 | 2 fails below |
| L4 | 12 pass, 1 fail, 3 blocked | |

## Fails
- PGR-04 (S2): ... steps, expected, seen
## Blocked / not run
- PRF-06: needs a second Kavita login
```

Screenshots from real servers are for the maintainer only and are never
committed (no commercial covers, no adult entries).

## Keeping this guide current

Every PR that adds or changes user-visible behaviour updates this page in
the same PR:

- **New feature:** add rows with a new ID in the right section (or a new
  section), a *Pass when* a stranger could judge, and the tests that cover it.
  Behaviour no test can check gets an **S** or **D** row instead.
- **Changed behaviour:** edit the row's *Pass when*. Don't renumber; a
  removed row's ID is retired.
- **New test class or file:** name it in a row's *Covered by*.
  `tools/check_testing_guide.py` (CI `ui-lint`) fails when a UI test class
  in `App/UITests` or a test file in `Packages/MangaCore/Tests` isn't named
  here, or when an ID is used twice.
- The PR template's testing checklist asks for this.
