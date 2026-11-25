# Design guide

How screens in this app should look on Apple TV. It follows Apple's
[tvOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)
and turns them into concrete numbers for this app. The numbers live in code in
`App/Sources/Shared/Design/DesignTokens.swift`; use the tokens instead of typing
numbers into views. When a screen needs a value the tokens don't have, add a
token here and in code rather than a one-off number.

All sizes are points on the 1920 × 1080 tvOS canvas (Apple TV 4K renders them
at 2×).

## 1. Principles

1. **Readable from the couch.** People sit 8+ feet away. Body text is 29 pt and
   nothing is smaller than 23 pt (HIG minimum).
2. **Room to breathe, but no runways.** Things shouldn't touch, and they
   shouldn't stretch across the whole TV either. A settings row that runs
   1,800 pt wide with its label at one end and its value at the other is as
   hard to read as one that's crammed.
3. **Let focus do the talking.** Use system focus effects (lift, scale,
   white platter). Leave room around every focusable item for it to grow
   about 10 % without covering its neighbours.
4. **System components first.** `Form`, `List`, `Picker`, `Toggle`,
   `TextField`, `Button` with system styles already have Apple's sizes,
   shapes and focus behaviour. Wrap them; don't redraw them.

## 2. Safe area and margins

| Token | Value | Source |
| --- | --- | --- |
| `Layout.safeTop` / `safeBottom` | 60 | HIG: inset primary content 60 pt top and bottom |
| `Layout.safeSide` | 80 | HIG: 80 pt from the sides |
| Tab bar | 68 tall, top edge 46 from the screen top | HIG (fixed by the system) |

SwiftUI already applies these insets. **Don't add your own 80 pt padding on top
of the safe area** (that doubles it to 160). Only use `Layout.safeSide` for
views that call `.ignoresSafeArea()`, such as the reader and the reader menu
drawer.

Full-bleed things (reader pages, backdrops) may ignore the safe area. Text and
focusable controls never do.

## 3. Spacing scale

An 8 pt grid with a few named steps. Pick the step by relationship, not by eye.

| Token | Value | Use for |
| --- | --- | --- |
| `Space.xxs` | 4 | Title to its subtitle inside one row |
| `Space.xs` | 8 | Icon to badge, tight label pairs |
| `Space.s` | 16 | Items inside one control (icon and label) |
| `Space.m` | 24 | Rows in a custom list, a label and its control |
| `Space.l` | 40 | Between focusable items side by side (HIG grid spacing), buttons in a row |
| `Space.xl` | 60 | Between sections of a page |
| `Space.xxl` | 80 | Between major regions (hero column and form column) |

Rules:

- Focusable neighbours are at least `Space.l` (40) apart horizontally, so the
  focused one can scale up without overlapping. Vertically, system list rows
  already include this room; custom stacks of buttons use at least `Space.m`.
- Grids follow the HIG minimum of 100 pt vertical spacing between unfocused
  rows of artwork, counting the caption under each poster.

## 4. Typography

Always use text styles (`.font(.headline)`), never fixed sizes, so Dynamic
Type and bold text keep working. tvOS sizes for reference:

| Style | Size / leading | Use in this app |
| --- | --- | --- |
| `.title` (Title 1) | 76 / 96 | Not used (too big for our screens) |
| `.title2` | 57 / 66 | Screen hero titles: series title, "Who's reading?" |
| `.title3` | 48 / 56 | Server names on Home and Library, empty-state titles |
| `.headline` | 38 / 46 | Shelf titles, section labels on custom pages |
| `.callout` | 31 / 38 | Secondary lines that still need emphasis (metadata, genres) |
| `.body` | 29 / 36 | Default: row labels, values, buttons, synopsis |
| `.caption` | 25 / 32 | Subtitles under row labels, poster titles |
| `.caption2` | 23 / 30 | Smallest allowed: badges, server name under a poster |

- `.footnote` and `.subheadline` aren't in the tvOS table; use `.caption` or
  `.body` instead.
- Avoid Light/Thin weights. Use `.semibold`/`.bold` for emphasis.
- Secondary text uses `.secondary`; never go lower than `.tertiary` for text
  someone needs to read.
- Long text (synopsis, explanations) stays within `Size.readableText` (1,100
  pt) so lines aren't longer than about 80 characters.

## 5. Corner radii

| Token | Value | Use for |
| --- | --- | --- |
| System | — | Buttons, list/form rows, text fields, pickers, toggles: keep the system shape |
| `Radius.poster` | 12 | Cover art (`.buttonStyle(.card)` rounds it too) |
| `Radius.card` | 20 | Custom tiles and grouped panels |
| `Radius.panel` | 32 | Large floating panels, e.g. the reader menu drawer if it gets corners |
| `Capsule()` | — | Badges, chips, standalone pill buttons |

Never mix a custom radius with a system one in the same row of controls. If a
custom control sits next to system buttons, use `Capsule()` (the HIG prefers
capsule or circular shapes for standalone buttons).

## 6. Sizes

| Token | Value | Use for |
| --- | --- | --- |
| `Size.minTarget` | 66 | Minimum height of anything focusable (system buttons and rows are 66–70) |
| `Size.buttonMinWidth` | 240 | Text buttons don't get stubby ("OK", "Save") |
| `Size.buttonMaxWidth` | 760 | Text buttons don't become bars; long labels truncate |
| `Size.formColumn` | 1,000 | Max width of a settings form column |
| `Size.heroColumn` | 600 | Width of the icon/artwork column beside a form |
| `Size.textField` | 800 | Max width of a free-standing text field |
| `Size.readableText` | 1,100 | Max line length of long text |
| `Size.messageText` | 900 | Max width of empty-state and error messages |
| `Size.icon` | 50 | Width reserved for leading row icons, so labels line up |
| `Size.avatarRow` | 52 | Profile avatar and the icon column inside a row (keeps every row the same height) |

### Poster grid

The HIG grid table (unfocused width / 40 pt horizontal spacing / ≥100 pt
vertical) gives seven columns of 217 pt across the 1,760 pt safe width. We use
that for shelves and library grids: `Grid.posterWidth` 217, height 1.5×,
`Grid.columnSpacing` 40, `Grid.rowSpacing` 100 (poster bottom to next poster
top, caption included).

## 7. Components

Shared views live in `App/Sources/Shared/Design/`. Use them for new screens.

### Settings pages (`SettingsPage`)

Every `Form`/`List` screen under Settings (and other configuration screens like
the server editor and category picker) uses the tvOS Settings layout:

```
| 80 safe | hero column 600 | 80 | form column up to 1,000 | 80 safe |
```

- The hero column shows a large SF Symbol (or the profile avatar) and the
  page title (`.title3` semibold) centered vertically, so the page has an
  anchor and the form isn't stretched across the whole TV.
- The form column scrolls by itself. Its rows keep the system look (rounded
  platter, white when focused).
- Use `Form` (not `List`) so every settings page has the same row and
  section rhythm.
- Every section has a header, and headers use `SettingsHeader` (or
  `Section(settingsHeader:)`): `.callout` semibold, secondary, title case,
  24 pt above and 16 pt below. Don't use `Section("Title")`: on tvOS its
  size and case differ between `List` and `Form`.
- Row icons go through `Label`; `SettingsPage` applies `.settingsRow`, which
  puts the icon in a 52 pt column with 24 pt before the text, so icon rows
  and avatar rows line up.
- Footers explain consequences in one or two short sentences.
- Order inside a form: what it is (name, type) → how to reach it (address,
  login) → options → actions. Destructive actions last, in their own section,
  with `role: .destructive` and a confirmation dialog.

```swift
Form { … }
    .settingsPage("Default Reader Settings", systemImage: "book")
```

- The page title sits under the symbol in the hero column, **not** in
  `.navigationTitle`. A navigation title above a scrolling form stays fixed on
  tvOS and ends up drawn over the rows, and it's centered on the screen
  instead of on the content.
- `.settingsPage(_:hero:)` takes any view for the hero (the profile editor
  shows the avatar being edited).

### Buttons

- Default: system `Button` in its default (bordered) style. On tvOS that is a
  rounded platter that turns white when focused.
- A row of actions uses `ActionRow { … }`: `Space.l` between buttons,
  leading-aligned, each at least `Size.buttonMinWidth` wide via
  `.actionButtonSizing()`.
- Primary action first (leading), then secondary, destructive last.
- Labels are verbs in Title Case ("Add Server", "Test Connection"), short
  enough to fit without truncation at `Size.buttonMaxWidth`.
- Icons in buttons use `Label(_, systemImage:)`, never a manual HStack.

### Text fields

- Inside a `Form` row, the system draws them at the right size.
- Outside a form, cap the width at `Size.textField` and give them a visible
  label or a prompt that says what to type. Prefer pickers or buttons when
  the choices are known (HIG: minimize text entry on tvOS).
- Show the right keyboard (`.keyboardType(.URL)`), and turn off
  autocorrection for names, addresses and keys.

### Rows

- Leading icon in a `Size.icon` frame, title in `.body`, optional subtitle in
  `.caption` `.secondary` `Space.xxs` below, trailing value in `.secondary`.
- One line each; truncate the middle part, never the value.
- Status words ("No API key") use `.caption` and a semantic color (`.orange`
  for attention, `.red` only for errors).

### Empty, loading and error states

- `BrowseMessage`: SF Symbol at 64 pt, title in `.title3`, message in `.body`
  `.secondary` capped at `Size.messageText`, one "Try Again" button when it
  can be retried.
- Loading: a single `ProgressView()` centered in the space the content will
  take, not at the top edge.

### Reader menu drawer

- Slides in from the trailing edge, 900 pt wide, full height, `.thickMaterial`.
- Ignores the safe area for its background only; its content is inset
  `Layout.safeTop` from the top and `Layout.safeSide` from the trailing edge.
- Option chips use `Capsule()` and `Space.m` between chips.

## 8. Focus

- Rely on system focus: `.buttonStyle(.card)` for artwork, the default style
  for buttons and rows. Custom styles (e.g. `ProfileTileButtonStyle`) scale to
  1.1 and add a shadow, nothing else.
- Every screen has a sensible first focus: the primary action (Continue on a
  series, the current profile in the picker, the first row in a form).
- Group regions with `.focusSection()` so moving down from a wide row of
  buttons lands somewhere predictable.
- Never move focus without the user doing something, except restoring it when
  a screen appears.
- Scrolling containers must scroll back to the top when focus moves to their
  first item, so titles and the tab bar come back into view. Don't put
  `.scrollClipDisabled()` on a vertical scroll view that sits under a
  navigation title.

## 9. Checklist for a new or changed screen

- [ ] No text or focusable control outside the 60/80 safe area.
- [ ] Nothing focusable shorter than 66 pt; text buttons 240–760 pt wide.
- [ ] Forms sit in `SettingsPage`; no row wider than 1,000 pt.
- [ ] Spacing uses `Space` tokens; focusable neighbours ≥ 40 pt apart.
- [ ] Only system text styles; nothing below `.caption2`.
- [ ] Corners: system shapes, or `Radius` tokens, or `Capsule()`.
- [ ] First focus is the obvious action; Menu goes back.
- [ ] Scrolling to the first item shows the title again.
- [ ] Looks right with the largest Dynamic Type size and with Bold Text on.

## Layout tests

`App/UITests/DesignLayoutUITests.swift` walks the screens it can reach without
a server and checks the rules a test can measure: focusable elements are at
least 60 pt tall (system rows report a few points less than they draw),
everything focusable stays inside the safe area (with room for focus growth),
form rows aren't wider than the form column, and sibling rows don't overlap.

Set `DESIGN_AUDIT_DIR` (as `TEST_RUNNER_DESIGN_AUDIT_DIR` for `xcodebuild`) to
also save a screenshot of every screen it visits to that folder. Those
screenshots are for local review only and must not be committed (see the
README's rule on sample content).
