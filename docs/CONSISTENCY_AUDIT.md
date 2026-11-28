# Consistency audit

An audit of main at `083170d` (2026-11-25) for places where features built in
parallel ended up doing the same thing in different ways. Each finding says
where it is, what differs, the standard to converge on, and how much it
matters:

- **High**: people notice it (different controls for the same job, labels
  that disagree, data that silently doesn't sync).
- **Medium**: visible on a close look, or a trap for the next change.
- **Low**: code tidiness.

Status: **Fixed** (in #46, or on the date given), **Guarded** (a CI check
now stops new cases), **Open** (left, usually because an open PR is changing
the same file; the note says when to do it).

Open PRs at the time (#7, #15, #17, #19, #23, #34–#43, #45) touch most screens, so
fixes here are limited to files no open PR changes. The open items are the
to-do list for after those merge.

## Guards added

| Check | Runs | What it stops |
| --- | --- | --- |
| `tools/check_design_tokens.py` | CI `ui-lint` job (seconds, Linux) | Literal corner radii, fixed font sizes on text, `.footnote`/`.subheadline`/`.title`, `Section("…")` headers, plain `Text` section headers (added 2026-11-27), "Retry" buttons. Covers `App/Sources` and `App/Sources-iOS` (the text-style rule is tvOS only). `BASELINE` is empty since 2026-11-28; keep it that way. |
| `SyncCoverageTests` (MangaCore) | `swift test` | A new `AppState` or `ProfileData` field that nobody classified as synced, device-only, or a known sync gap. |
| `tools/check_setting_scopes.py` | CI `ui-lint` | A `ReaderSettings` field (settable per series from the reader menu) with no row in Default Reader Settings. Book-specific fixes are exempt with a reason. |
| `tools/check_pinned_headers.py` (existing) | CI `ui-lint` | `.navigationTitle`, and `.scrollClipDisabled()` on vertical scroll views. |

## 1. Reader controls

| # | Where | What differs | Standard | Severity | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | `PagedReaderView`, `BookReaderView` vs `WebtoonStripController.handlePress` | Clicking the center (Select) opens the menu in the vertical reader but does nothing in the paged and book readers, which open it with swipe down or Play/Pause. | Select opens the menu in every reader (Play/Pause stays as a second way in paged and book). Coordinate with #17, which uses click for zoom in the paged reader: if click zooms there, document that and keep Down/Play/Pause as the menu. | High | **Fixed** by #45, then replaced by #67: holding Play/Pause opens the options in every reader (docs/CONTROLS.md) |
| R2 | `BookReaderView` vs `ReaderView` | The book reader never registers with `GameControllerHub`, so shoulder buttons, triggers and Y do nothing in EPUB/text books, while README says controllers work "in the reader". | Book reader pushes a handler: L1/R1 turn pages, L2/R2 change chapter, Y toggles the drawer, like the paged reader. | High | Open, unblocked since #67 merged (needs a device check; next run) |
| R3 | `BookReaderContent.handleMove` vs `PagedReaderView.handleMove` | Up bookmarks the page in the image readers; in the book reader Up does nothing and there are no bookmarks. | Either add book bookmarks or keep Up unused there and say so in the help text. | Medium | Open |
| R4 | `ReaderMenu` vs `BookReaderMenu` | Two drawer shells with the same 900 pt width, `.thickMaterial`, Play/Pause-to-close and focus timing copied. Padding is 60 pt on both sides; DESIGN_GUIDE §7 says `Layout.safeTop` top and `Layout.safeSide` (80) trailing. | One `ReaderDrawer` view in `Shared/Design` that owns width, material, padding (tokens), Play/Pause and the first-focus hop. | Medium | Open, unblocked since #67 merged (a refactor; next run) |
| R5 | `ReaderLoadStateView` (`ReaderView`), `BookLoadStateView` (`BookReaderView`), `ChapterTransitionCard` (`PagedReaderView`) | Error and edge panels use `.regularMaterial` with radius 24, the paged edge card `Color(white: 0.12)` with radius 32, literal paddings (60, 80, 120). | Reader overlays use `Radius.panel` and `.regularMaterial`; padding from `Space`. | Medium | **Fixed** 2026-11-28 (`Radius.panel`; paddings still literal) |
| R6 | Reader errors vs `BrowseMessage` | Reader errors say "Retry"; every browse screen and the design guide say "Try Again". | "Try Again" everywhere. | Medium | **Fixed** 2026-11-28 (paged, vertical, book and webtoon error cards; guarded) |
| R7 | Webtoon vs paged/book | Play/Pause toggles auto-scroll in vertical but opens the menu in paged and book. | Acceptable (auto-scroll is the vertical reader's play action) but the menu's help line should say what Play/Pause does in the current mode. | Low | **Fixed** by #67: Play/Pause plays in every reader (auto-scroll or page timer), hold opens options |

## 2. Labels and wording

| # | Where | What differs | Standard | Severity | Status |
| --- | --- | --- | --- | --- | --- |
| W1 | `ReaderDefaultsView` vs `ReaderMenuItem.title` (MangaCore) | The same settings have different names and case: "Mode" / "Reading Mode", "Pages" / "Page Layout", "Column width" / "Column Width", "Show first page alone" / "First Page Alone", "Scroll per click" (no menu twin). | Default Reader Settings uses `ReaderMenuItem.title` for every row it shares with the menu, Title Case for the rest. | High | **Fixed** 2026-11-27: Default Reader Settings rows use `ReaderMenuItem.title` / `PictureMenuItem.title` |
| W2 | `ReaderDefaultsView` "Reset to Defaults" vs `ReaderMenu` "Reset to Default" | Singular vs plural for the same idea. | "Reset to Default" in the menu (one default to go back to), "Reset to Defaults" on the settings page (all of them). Fine as is if intended; otherwise pick one. | Low | Open |
| W3 | `BookReaderView` "isn't available for this source" | "source" appears nowhere else; the app says "server". | "server". | Low | **Fixed** 2026-11-28 |
| W4 | `CategoryPickerView` loading/failed rows | "Couldn't load libraries. Try Again" is one button label with the action glued to the error. | Error as the row's title, "Try Again" as its own button, like `BrowseMessage`. | Low | **Fixed** 2026-11-26: error text row plus its own Try Again button |
| W5 | Context menus (`BookmarksView`, `SeriesBookmarksSection`, `ReaderMenu`, `SeriesPoster`, `SeriesDetailView`) | Some items are `Label` with an SF Symbol ("Mark as Unread"), others plain text ("Remove Bookmark", "Go to Series"). | Every context-menu item is a `Label` with a symbol. | Low | Partly fixed 2026-11-26 (`SeriesBookmarksSection`); `BookmarksView`, `ReaderMenu` open |
| W6 | Category nouns | Consistent: `ServerKind.categoryNoun` gives Libraries / Categories / Sections / Collections and every screen uses it. | Keep it; never hard-code "Libraries". | — | OK |

## 3. Visual tokens

| # | Where | What differs | Standard | Severity | Status |
| --- | --- | --- | --- | --- | --- |
| V1 | `WiFiBackupView`, `SeriesDetailView`, `AlphabetJumpBar` | Literal radii 20, 12, 8. | `Radius.card`, `Radius.poster`, new `Radius.small`. | Medium | **Fixed**, guarded |
| V2 | `SeriesPoster.FormatBadge`, reader overlays | Literal radii 6, 24, 32. | `Radius.small`, `Radius.panel`. | Medium | **Fixed** 2026-11-27 for the format badge (`Radius.small`); reader overlays open with R5 |
| V3 | `AlphabetJumpBar` | 22 pt letters, below the 23 pt minimum in DESIGN_GUIDE §1. | 23 pt (fixed size kept so 27 letters fit the column, marked `design-ok`). | Medium | **Fixed** |
| V4 | `ReaderMenu` help lines | `.footnote`, which the guide says isn't in the tvOS table. | `.caption`. | Low | **Fixed** 2026-11-28 |
| V5 | Spacing and padding across `App/Sources` | About 141 literal `spacing:`/`.padding(` values (20, 30, 12, 14, 28, 36, 50, 70, 120…) next to the `Space` scale; about half aren't on the 8 pt grid. Worst: `BookmarksView` (20/30 page insets), `SeriesDetailView` (20, 10), `HomeView`/`LibraryView` loading spinners (`.padding(80)` vs `.padding(40)`). | `Space` tokens. Not yet in the lint because nearly every file has some; add a `spacing` rule with a baseline once the open PRs land. | Medium | Open |
| V6 | `BrowseMessage` (`SeriesPoster.swift`) | Uses 24 / 900 / 60 literals for what DESIGN_GUIDE calls `Space.m` / `Size.messageText` / `Space.xl`. | Tokens. | Low | **Fixed** 2026-11-27: `Space.m`, `Size.messageText`, `Space.xl` |
| V7 | `RootView.PlaceholderView` | Unused, and pads 80 pt on top of the safe area (the guide's "don't double the margin"). | Delete. | Low | **Fixed** 2026-11-27: deleted |
| V8 | `ScreenTitle` | Unused on main; only #19's `ContentSettingsView` still uses it. | Move that screen to `.settingsPage` and delete `ScreenTitle`. | Low | **Fixed** 2026-11-27: Content & PIN is a `Form` in `.settingsPage`; `ScreenTitle` deleted |

## 4. Screens and states

| # | Where | What differs | Standard | Severity | Status |
| --- | --- | --- | --- | --- | --- |
| S1 | `SearchView` per-server errors, `BookmarksView` open errors | Plain `Text` lines in secondary color; other screens use `BrowseMessage`. | `BrowseMessage` (with Try Again where it can retry), or an inline row with the same icon and wording. | Medium | Open (#40, #19) |
| S2 | Loading spinners | `ProgressView().frame(maxWidth: .infinity).padding(80)` (Home, Library, Search), `.padding(40)` (Library paging), bare in a Form row (category picker, server test). | A shared `LoadingView` centered in the content area (DESIGN_GUIDE §7). | Low | Open |
| S3 | Save model | Server editor, profile editor and category picker have Save buttons; Default Reader Settings, Customize Home, Sort & View, Free Library apply as you change them. | Creating something needs Add/Save; editing an existing thing applies immediately, like Apple's Settings. The category picker (editing) is the odd one. | Medium | **Fixed** by #57 (settings apply as they change; only the server form keeps Save) |
| S5 | `ContentSettingsView`, `ICloudSyncView` | Section headers were plain `Text` (system dim header) instead of `SettingsHeader`; Content & PIN was a `List` with `ScreenTitle`. | `SettingsHeader`, `Form` + `.settingsPage`. | Medium | **Fixed** 2026-11-27, guarded |
| S6 | `ReaderDefaultsView` Picture section | Brightness, Contrast, Color, Sharpen and Upscaling used the system `Picker` (value far from the chevron) while every other row uses `SettingsPicker`. | `SettingsPicker`. | Medium | **Fixed** 2026-11-27 |
| S4 | Settings sections | DESIGN_GUIDE says every section has a header; `ServerEditorView`, `ICloudSyncView`, `CategoryPickerView`, `LibraryOptionsView`, `ReaderDefaultsView`, `FreeLibrarySettingsView` have header-less sections (footer-only or action sections). | Allow header-less sections only for the final actions section; say so in the guide. | Low | Open |

## 5. Code

| # | Where | What differs | Standard | Severity | Status |
| --- | --- | --- | --- | --- | --- |
| C1 | 13 call sites | Error text is built three ways: `(error as? LocalizedError)?.errorDescription ?? error.localizedDescription` (8), `error.localizedDescription` (4), `engine.lastError ?? …` (1). | One `Error.userMessage` helper in MangaCore. | Low | Open |
| C2 | Whole app | No logging at all (no `Logger`/`os_log`), and 162 `try?` that drop errors. Sync, image and network failures leave no trace on a device. | `Logger(subsystem: "com.rustedimac.MangaReader", category: …)` per area; log the error before every `try?` that hides a failure the user might report. | Medium | Open |
| C3 | Accessibility identifiers | `lowerCamel.dotted` everywhere except `RemoteImage.loaded/failed/loading` (PascalCase), and `bookmark.*` vs `bookmarks.*`, `category.*` vs `categories.*` for related screens. | `screen.element[.detail]`, lowerCamel. Rename `RemoteImage.*` to `remoteImage.*` together with its UI tests. | Low | Partly fixed 2026-11-26: `remoteImage.*`; bookmark/category prefixes open |
| C4 | Focus hops | `DispatchQueue.main.async { focus = … }` in `ReaderMenu`, `BookReaderMenu`, plus `asyncAfter` retries (0.1/0.4/1.0 s) in `WebtoonReaderView`. | One `.focusOnAppear(_:)` helper with the run-loop hop documented once. | Low | Open |
| C5 | Tests | Consistent: MangaCore tests are XCTest `FooTests`, UI tests `FooUITests` with `testDoesSomething` names and `-uiTesting` launch flags. | Keep. | — | OK |
| C6 | `tools/__pycache__/` | A compiled `.pyc` was committed with #80; nothing ignored Python bytecode. | `.gitignore` ignores `__pycache__/` and `*.pyc`. | Low | **Fixed** 2026-11-28 |

## 6. Per-series settings and global defaults

Rule (John, 2026-11-25): every per-series (or per-library) setting also has
a global default, the narrower value only overrides it, and it can be reset
to the default. Added to DESIGN_GUIDE §7 "Setting scopes".

| # | Setting | Narrow scope | Global default today | Status |
| --- | --- | --- | --- | --- |
| G1 | Reading mode, direction, page layout, first page alone, background, column width, scroll per click | Per series (reader menu) | Default Reader Settings; menu has Set as Default / Reset to Default | OK, guarded |
| G2 | Crop borders, page fit, click-to-zoom (#17) | Per series | Rows added to Default Reader Settings in #17 | OK (checked against #17's head), guarded |
| G3 | Split wide pages, brightness, contrast, color, sharpen, upscaling (#35) | Per series | Rows added in #35 | OK (checked against #35's head), guarded |
| G4 | Shift page pairing | Per series | None | Retired: it did the same as First Page Alone (G1), so it was folded into it. |
| G5 | Library sort (`LibraryOptions.sort`) | Per library (Sort & View) | Library Defaults | Fixed 2026-11-26: Library Defaults screen, "Default (…)" rows and Reset to Defaults on Sort & View. |
| G6 | Grid order (`LibraryOptions.gridOrder`) | Per library | Library Defaults | Fixed 2026-11-26 (same as G5). |
| G6b | Library filters (`LibraryOptions.filter`) | Per library | Library Defaults (status, read progress) | OK. Genres are exempt: each library has its own genre list. |
| G7 | Library reading style (`LibraryOptions.readingStyle`) | Per library | Default Reader Settings direction | OK; Reset to Defaults on Sort & View clears it. |
| G8 | Auto-scroll speed, book text settings, poster size, poster caption (#41) | Profile only | They are the global value | OK (no per-series override exists). |
| G9 | Wording | Default Reader Settings and the reader menu name the same settings differently (W1). | **Fixed** 2026-11-27 (W1) |

## 7. Sync coverage

`SyncMapper` syncs servers, profiles, per-server settings, favorites,
progress, default and per-series reader settings, and browse preferences.
Everything else a profile changes stays on one Apple TV, and docs/ICLOUD.md
doesn't say so:

| # | Field | Severity | Status |
| --- | --- | --- | --- |
| Y1 | `ProfileData.bookmarks` (page bookmarks; Kavita/Suwayomi sync some server-side, the rest are device-only) | High | Open: needs a `bookmark` kind keyed by `Bookmark.id`. |
| Y2 | `ProfileData.bookSettings` (EPUB text size, font, theme) | Medium | Open |
| Y3 | `ProfileData.favoritesSort` | Low | Open |
| Y4 | `ProfileData.webtoonAutoScrollLevel` | Low | Open (could join `readerDefaults`). |
| Y5 | `BookPositionStore` (in-chapter book position, separate UserDefaults key) | Medium | Open |
| Y6 | `AppState.freeLibraryRemoved` | Low | Open: removing the Free Library on one device brings it back on the next sync of another. |

`SyncCoverageTests` lists these as known gaps; take a field off the list when
its domain lands. `SyncMapper.swift` is being changed by #43, so the domains
should follow that merge.

## 8. Docs

| # | Where | What's stale | Status |
| --- | --- | --- | --- |
| D1 | README intro | Named only Kavita and Suwayomi; no Komga, OPDS, Free Library, PDF/EPUB or Apple TV users. | **Fixed** |
| D2 | README Tests | "CI runs both on every push and pull request"; pushes to branches no longer run CI (docs/CI.md). | **Fixed** |
| D3 | README "Connecting servers" | Only Kavita and Suwayomi. | **Fixed** 2026-11-26: Komga, OPDS and Free Library bullets, link to docs/SERVERS.md |
| D4 | DESIGN_GUIDE §7 Settings headers | Says "primary at 75 % opacity"; `SettingsHeader` uses 0.8. | **Fixed** 2026-11-26: guide says 80 %, matching the code |
| D5 | DESIGN_GUIDE §7 Reader drawer | Says content is inset 80 pt from the trailing edge; both drawers use 60. | Open (see R4). |
| D6 | docs/ICLOUD.md "What syncs" | Doesn't list bookmarks, book settings, Favorites sort, auto-scroll speed or book positions as not synced; Follow-ups still describe #14 bookmarks as "after this lands". | Open (#34, #35, #41, #43 edit it). |
| D7 | Project plan (`plan/work-breakdown.md`) | No status per workstream, and nothing on Komga/OPDS, Free Library, books, iCloud or Apple TV users, which were all added later. | Open (project file, not in the repo). |
| D8 | `tools/check_design_tokens.py` | Scanned only `App/Sources`, so the iOS sources (#82, #85–#87) weren't checked. | **Fixed** 2026-11-28: it scans `App/Sources-iOS` too (text-style rule skipped there). |
| D9 | docs/READER_CONTROLS.md | Still opened with "proposal, nothing implemented yet" after #67 implemented section 10. | **Fixed** 2026-11-28: marked as the design record, pointing to docs/CONTROLS.md. |

## Run log

- 2026-11-25: first audit, #46.
- 2026-11-26 (nightly): #15, #36, #37, #38, #39, #41, #51 merged; lint clean, no new findings. Fixed W4, D3, D4, part of W5 and C3.

- 2026-11-27 (nightly): 33 PRs merged (#17, #19, #34, #35, #43, #45, #56, #57 and others); lint clean. New finding S5 (plain `Text` section headers in Content & PIN and iCloud) fixed and guarded; Default Reader Settings picture rows were system `Picker`s, now `SettingsPicker` (S6). Fixed W1, V2 (badge), V6, V7, V8. Next: sync domains (Y1–Y6), now that #43 is in.
- 2026-11-28 (nightly): 9 PRs merged (#67, #80–#87, including the iOS app). Lint clean. Fixed R5 (radius), R6, W3 and V4 now that #67 is in, and #67 settled R7; the design-token `BASELINE` is empty. New: the token lint now also covers `App/Sources-iOS` (D8); docs/READER_CONTROLS.md still said "nothing implemented yet" after #67 (D9, fixed); a `.pyc` was committed in `tools/__pycache__` (C6, removed and ignored). Still open: R2 (book reader controller), R4 (one drawer view), Y1–Y6 sync domains.

## Not checked

The simulator walk-through. DesignLayoutUITests already measures sizes,
margins and overlaps on every reachable screen, and controller and focus
behaviour needs a device, so R1, R2 and R5 should be confirmed on the Apple TV
when they're fixed.
