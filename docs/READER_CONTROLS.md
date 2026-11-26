# Reader controls: current behaviour, conflicts and proposal

Status: **proposal for review, nothing implemented yet.** Written 2026-11-26
after John asked why Down and Play/Pause both open the reader options, why
Back leaves the chapter while the options are open, and that the page number
pill should not be on screen all the time.

Once John picks a scheme, the implementing PR updates `ReaderControls`
(MangaCore), the Settings > Remote and Controller screen and `docs/CONTROLS.md`
(from PR #45) to match, and this file becomes the design record.

Sources read: `main` at dd285e2, plus the branches of the open reader PRs
#17 (fit/crop/zoom), #45 (one-click options, hint), #58 (First Page Alone),
#59 (menu tabs).

---

## 0. Short answers

| Question | Answer |
| --- | --- |
| Why do both Down and Play/Pause open the options (paged reader)? | Both are wired to it on purpose. `PagedReaderView.handleMove` sends `.down` to `isMenuPresented = true`, and `.onPlayPauseCommand` does the same. The first reader copied Mihon's "swipe down for the sheet" and used Play/Pause because tvOS has no context button. PR #45 adds a third way (click). The book reader does the same. Nothing else uses Play/Pause in paged mode, so it was "free", but it means Play/Pause does a different thing in each mode. |
| Why does Back leave the chapter while the options are open? | The intent is close-first: `ReaderView.onExitCommand` closes the options if `isMenuPresented`, otherwise closes the reader. The UI tests confirm it, **but they only run the reader as the app's root view** (`-readerDemo`). In the real app the reader is a `fullScreenCover` (from Series detail, Bookmarks, Top Shelf). `onExitCommand` only fires when focus is inside the view it is attached to; the menu sets its focus on the next run loop turn while the page underneath is `.disabled`. If the Menu press arrives while focus is nowhere (or on a view outside that subtree), the cover's own Back handling dismisses the whole reader. That path is untested. Fix in section 5. |
| Will auto-scroll on Play/Pause clash with paged mode? | Today, yes: Play/Pause is auto-scroll in vertical and "open options" in paged/book. The proposal gives Play/Pause one meaning everywhere ("play": auto-scroll in vertical, timed auto-advance in paged) and takes the options off it. |
| Should the page pill always show? | No. Apple's own player hides its controls until you rest a finger on the touch surface, and hides them with Back. Proposal: a light **tap** (not a click) shows the HUD, it hides itself after a few seconds, with a setting for Always / On tap / Never. |

---

## 1. Current behaviour (main + open PRs)

### 1.1 Siri Remote inputs we can tell apart

| Input | What tvOS gives the app | Notes |
| --- | --- | --- |
| Click centre (Select) | `select` press; SwiftUI `onTapGesture` | SwiftUI's "tap" on tvOS is a click. |
| Hold Select | `select` press with long duration; `onLongPressGesture` | Some sim viewers can't hold a key (why #45 adds a "…" button for chapter options). |
| Tap the touch surface, no click | Indirect touch only. Needs a UIKit `UITapGestureRecognizer` with `allowedTouchTypes = [.indirect]`, `allowedPressTypes = []` | Not used anywhere yet. HIG: "differentiate between press and tap, and avoid responding to an inadvertent tap." A resting thumb can tap. |
| Rest finger on surface | Touch began, no movement | Apple TV app uses this to show transport controls. |
| Swipe | Indirect pan; in SwiftUI focus moves become `onMoveCommand` | Webtoon uses its own pan recognizer (momentum). |
| Click ring edge up/down/left/right (2nd/3rd gen remote) | Arrow press; `onMoveCommand` | On the 1st-gen remote a tap near an edge can also arrive as an arrow press. |
| Circle on the ring (jog) | Touch positions only (GameController micro gamepad absolute d-pad) | Infuse uses it for scrubbing. No direct API; would be custom. |
| Play/Pause | `playPause` press; `onPlayPauseCommand` | Hold is possible via raw presses. |
| Back / Menu | `menu` press; `onExitCommand` | Holding Back goes Home (system). |
| TV/Home, Siri, volume, mute, power | System | Never available to the app. |

### 1.2 Paged reader (single / double page, LTR / RTL; PDFs open here too)

| Input | main today | PR #17 (fit/zoom/crop) | PR #45 (one-click options) |
| --- | --- | --- | --- |
| Click | Retries a failed page on screen, otherwise nothing | Retry, otherwise **zoom in / out** | Retry, otherwise **open options** |
| Hold Select | Nothing | Nothing | Open options |
| Play/Pause | **Open options** | Open options | Open options |
| Swipe/click down | **Open options** | Pan down if the page is taller than the screen, otherwise open options | Open options |
| Swipe/click up | Toggle bookmark | Pan up if possible, otherwise toggle bookmark | Toggle bookmark |
| Swipe/click left/right | Turn page (follows reading direction). Past the last/first spread: transition card, press again to change chapter | Pan sideways if zoomed / Fit Height; pressed toward an edge already reached, turn. Finger on the touch surface drags the page freely | Same as main |
| Back | Close options, else close reader (bug above) | **Zoom out first**, then as main | Same as main |
| Tap (no click) | Nothing | Nothing | Nothing |

**Conflict:** #17 and #45 both claim the click. Whichever merges second must
choose (section 6, decision D2).

### 1.3 Vertical (webtoon) reader

Handled in UIKit (`WebtoonStripController.handlePress`, own pan recognizer).

| Input | main today | PR #45 |
| --- | --- | --- |
| Click | Auto-scroll running: stop it. Otherwise retry failed page, else **open options** | Same, decided on release |
| Hold Select | Same as click | **Open options** even while auto-scrolling (0.5 s) |
| Play/Pause | **Start/stop auto-scroll** | Same |
| Swipe up/down | Scroll with momentum. While auto-scrolling: faster/slower | Same |
| Click up/down | Step `webtoonScrollStep` of a screen, hold to keep scrolling. While auto-scrolling: faster/slower | Same |
| Click left/right | Snap to previous/next page | Same |
| Back | Close options, else close reader (same bug) | Same |

### 1.4 Book reader (EPUB, text)

| Input | main today | PR #45 |
| --- | --- | --- |
| Click | Nothing | Open options |
| Hold Select | Nothing | Open options |
| Play/Pause | Open options | Open options |
| Swipe/click down | Open options | Open options |
| Left/right | Turn page | Same |
| Back | Close options, else close book (`BookReaderView.onExitCommand`, same cover risk) | Same |

### 1.5 Inside the reader options and page scrubber

| Input | Reader options (drawer) | Page scrubber ("Pages" button, #35) |
| --- | --- | --- |
| Arrows | Move focus; tabs Settings / Chapters / Bookmarks (#59 restyles them) | Left/right: next thumbnail. Up/down: jump 10 pages |
| Click | Pick option / button | Jump to that page and close |
| Play/Pause | Close | Close |
| Back | Close the drawer (when it works) | **Closes everything**, not back to the drawer (`isMenuPresented = false` drops both) |

### 1.6 Game controller today (`GamepadMapping`, `GameControllerHub`)

tvOS turns the d-pad, A and B into arrow, Select and Back presses, so they act
exactly like the remote. The reader listens directly to the rest.

| Button | Paged | Vertical | Menu open |
| --- | --- | --- | --- |
| D-pad | = remote arrows | = remote arrows | Moves focus |
| A | = click | = click | Picks |
| B | = Back | = Back | = Back (same bug) |
| L1 / R1 | Turn page left/right | Previous/next page | Ignored |
| L2 / R2 | Previous/next chapter | Previous/next chapter | Ignored |
| X | Nothing | Toggle auto-scroll | Ignored |
| Y, Options/View/Share | Toggle options | Toggle options | Closes |
| Either stick | Nothing | Smooth analog scroll (quadratic, dead zone 0.15) | Ignored |
| ☰ Menu, L3/R3, PS touchpad | Not used | Not used | Not used |

### 1.7 HUD elements today

| Element | Where | When it shows |
| --- | --- | --- |
| Page pill "2–3 / 31" | Paged, bottom centre | **Always**, whenever pages are loaded |
| Chapter + page pill "Ch 3 · 12 / 40" | Vertical, bottom centre | **Always** |
| Auto-scroll badge "Speed 3 of 10" | Vertical, above the pill | While auto-scroll runs |
| Position line "Page 4 of 120 · 3%" | Book, bottom | Always |
| Bookmark ribbon | Top right | While a bookmarked page is on screen and options are closed |
| Notice capsule ("Bookmarked") | Top centre | A moment after an action |
| Zoom badge (#17) | Corner | While zoomed |
| First-use hint (#45) | Top centre | First 3 opens per mode, 8 s |
| Transition card | Centre | Past the first/last page |

---

## 2. How other apps do it

| App | HUD shows when | HUD hides | Back with HUD up | Play/Pause | Source |
| --- | --- | --- | --- | --- | --- |
| Apple TV app (video) | Paused, or **rest a finger on the touch surface**, or press up on the ring | Back/Menu, or after a few seconds of no input while playing | Closes pop-ups and the controls first, cancels a scrub | Play/pause | [Apple: Control video playback](https://support.apple.com/guide/tv/control-video-playback-atvb7944597f/tvos) |
| Apple TV app, extra panels | Swipe down = info panel, swipe up = subtitles | Back | Closes the panel | | same |
| Infuse | Click or Play/Pause pauses and shows controls; edge clicks skip 10 s; swipe down opens playback options; jog wheel on the ring scrubs | Timeout | Closes | Play/pause | [Infuse: Playback Controls](https://support.firecore.com/hc/en-us/articles/215090987-Playback-Controls); users ask for edge taps to skip *without* showing the HUD ([forum](https://community.firecore.com/t/infuse-tvos-suppress-playback-gui-during-skipping-via-siri-remote-tap/56270)) |
| Apple HIG | Use taps for showing info, not for actions; ignore accidental taps; Back opens the parent screen, in games Back opens a pause menu | | Back = one level up | Media: play/pause; games: secondary button | [HIG: Remotes](https://developer.apple.com/design/human-interface-guidelines/remotes) |
| Netflix / Plex (tvOS) | Any click or touch shows the controls; they fade after a few seconds | Timeout or Back | Back hides the controls before leaving | Play/pause | From general use, not re-checked for this doc |
| Mihon / Kindle / Kavita web (touch) | Tap the middle of the page shows the menu + progress bar; page number is a setting (Mihon: "Show page number") | Tap again, or turn the page | Closes the menu first | n/a | Mobile apps; no Kindle on tvOS |
| tvOS comic readers (KMReader for Komga, theXReader) | KMReader advertises "tvOS remote controls" but doesn't document them; theXReader is new and undocumented | | | | [KMReader](https://everpcpc.github.io/KMReader), [theXReader](https://forums.plex.tv/t/thexreader-app-comic-book-reader/941252) |

**What they agree on:** the content is clean by default; a light touch shows a
HUD that fades by itself; Back always peels one layer (HUD, panel, menu)
before leaving; Play/Pause means "play".

---

## 3. Feature matrix: every reader feature mapped to controls

Status: **A** available on main, **PR** in an open PR, **P** planned/proposed.
"Now" is what does it today; "Proposed" is the recommended scheme (section 4).
⚠ marks a conflict today.

| Feature | Status | Paged now | Vertical now | Proposed remote | Proposed gamepad |
| --- | --- | --- | --- | --- | --- |
| Turn page / next page | A | Left/right | Click left/right (snap) | Same | D-pad L/R, L1/R1 |
| Scroll | A | n/a | Swipe, click up/down | Same | Left stick (analog), d-pad up/down |
| Chapter transition card | A | Press past edge | Strip joins chapters | Same | Same |
| Previous / next chapter | A | Transition card, Chapters tab | Strip, Chapters tab | + HUD buttons | L2/R2 |
| Open reader options | A | ⚠ Down **and** Play/Pause (+ click in #45) | Click (+ hold in #45) | **Click** in every mode | ☰ Menu (or Y, D5) |
| Show/hide HUD (page, chapter, progress) | P | Always on | Always on | **Tap** (no click); auto-hide 3 s | View/Options, PS touchpad tap |
| Bookmark page | A | Up | Options > Bookmark | Up (paged, nothing to pan); Options button everywhere | Y |
| Bookmarks list | A | Options > Bookmarks tab | Same | Same | Same |
| Chapters list | A | Options > Chapters tab | Same | Same | Same |
| Page scrubber / page jump | A (#35) | Options > Pages | Options > Pages | **Down** (paged, nothing to pan) or HUD; vertical: via HUD/options | View/Options then d-pad |
| Jump to page number | P | — | — | Scrubber: up/down ±10 (exists); number entry later | Same |
| Zoom in / out | PR #17 | ⚠ Click (#17) vs options (#45) | — (planned) | **Hold Select** toggles zoom (D2) | Right stick up/down (analog), R3 resets |
| Pan when zoomed / Fit Width | PR #17 | Arrows pan before turning | — | Same | Left stick (analog) + d-pad |
| Fit screen/width/height, crop borders | PR #17 | Options | — | Options | Options |
| Auto-scroll start/stop | A | — | Play/Pause; X | **Play/Pause** | X |
| Auto-scroll speed | A | — | Swipe/click up/down while running | Same | Right stick or L2/R2 while running (D6) |
| Auto-advance pages (timed) | P | — | — | **Play/Pause** in paged (D3) | X |
| Mark chapter read | PR #45 (series page) | — | — | Options > Chapters "…" ; auto at end (exists) | Same |
| Picture controls (brightness, contrast, colour, sharpen, upscale) | A (#35) | Options | Options | Options; maybe quick brightness in HUD | Same |
| Split wide pages | A (#35) | Options | — | Options | — |
| First Page Alone (incl. shift) | A, PR #58 | Options | — | Options | — |
| Layout single/double, direction, mode | A | Options | Options | Options | — |
| Webtoon width | A | — | Options | Options | — |
| Background colour | A | Options | Options | Options | — |
| Retry failed page | A | Click on failed page | Click | Same (click retries before opening options) | A |
| Close reader | A | ⚠ Back (cover bug) | ⚠ Back | Back after all layers closed (section 5) | B |
| Horizontal continuous scroll | P (nice-to-have) | — | — | As vertical, axes swapped | Left stick X |
| Book: turn page, options, contents | A | Left/right, Down/Play/Pause | — | Left/right; click = options; tap = HUD | D-pad, ☰ |

---

## 4. Recommended scheme

One rule per input, the same in every mode:

| Input | Meaning everywhere | Paged | Vertical | Book |
| --- | --- | --- | --- | --- |
| **Tap** (touch, no click) | Show/hide the HUD | ✓ | ✓ | ✓ |
| **Click** | Reader options | Options (retries a failed page first) | Options (stops auto-scroll first only if D4 says so) | Options |
| **Hold Select** | Secondary "look closer" action | Zoom in/out (#17) | Reserved (webtoon zoom later) | Nothing |
| **Play/Pause** | Play | Auto-advance pages on a timer (D3) | Auto-scroll start/stop | Auto-advance (or nothing) |
| **Left/right** | Move through the book | Turn (pan first if zoomed) | Previous/next page | Turn |
| **Up/down** | Move within the page | Pan; at the top **Up = bookmark**; at the bottom **Down = page scrubber** | Scroll | Nothing (Down = scrubber/contents) |
| **Back** | Close one layer | see section 5 | | |

### HUD (heads-up display)

- Contents: top bar with series and chapter title; bottom bar with a thin
  progress bar, "2–3 / 31", a bookmark icon if bookmarked, and the auto-scroll
  speed when running. Optional quick buttons later (chapter back/forward).
- Shows on a tap, for 2 s when a chapter opens, when changing chapter, and
  while auto-scroll speed is changing. Hides after 3 s with no input, on any
  page turn (setting), on Back, or on another tap.
- Setting (global default plus per-series override, per John's settings
  rule): **Page number: On tap (default) / Always / Never.** "Always" keeps
  today's small pill only; the full HUD still needs a tap.
- Tap filtering (HIG): count a tap only if the touch is short (< 0.25 s),
  barely moves, and no press happened during it. Taps during auto-scroll
  still show the HUD (it doesn't change anything, so a stray tap is harmless).
- Under VoiceOver or Reduce Motion: the HUD stays until dismissed and fades
  without movement.
- Game controller has no touch surface: View/Options toggles the HUD, and
  the DualShock/DualSense touchpad tap does too.

### Alternatives worth considering

| Scheme | Click | Tap | Play/Pause | Down (paged) | Hold Select | Trade-off |
| --- | --- | --- | --- | --- | --- | --- |
| **A. Recommended** (above) | Options | HUD | Play (auto-scroll / auto-advance) | Scrubber | Zoom | Consistent; zoom is one step less discoverable. |
| B. "Video app" | HUD + transport (options button inside the HUD) | HUD | Play | Options | Zoom | Most like Apple TV app; options are two presses away. |
| C. "Click to zoom" | Zoom (#17 as is) | HUD | Play | Options | Options | Zoom easiest; options need swipe down or hold, which is what John found hard to find before #45. |

---

## 5. Back / Menu stack rules

Back always closes the top-most layer. Only when nothing is open does it
leave the reader (saving progress first). Order, top first:

1. A popover or picker inside the options (system handles it).
2. Page scrubber → back to the options drawer (not all the way out).
3. Reader options drawer → reading.
4. HUD visible → hide HUD.
5. Zoomed in (#17) → zoom out.
6. Auto-scroll / auto-advance running → stop it. (Optional, D7; Apple's player doesn't need this because the HUD is up while playing.)
7. Transition card → back to the last page (optional).
8. Otherwise → close the reader.

Implementation notes for the fix PR:

- One `ReaderSession.back() -> Bool` that pops the stack above, called from a
  single `onExitCommand` that is attached to **both** the reader root and the
  overlays, so it fires wherever focus is. The webtoon UIKit view keeps
  passing `menu` up the responder chain.
- Never leave focus empty while an overlay opens: give the drawer
  `defaultFocus` synchronously and keep the page focusable (not `.disabled`)
  until the drawer has focus, or attach the exit handler to the container
  that always has focus.
- Add a UI test that opens the reader **through a `fullScreenCover`** (Series
  detail or a test host that mirrors it), opens options, presses Menu, and
  asserts the reader is still there. Today's tests use the reader as the
  root view and can't catch this.
- Game controller B is the same press, so it gets the same stack for free.
  Y/☰ toggling the options must also respect it (closing the scrubber
  returns to the drawer).

---

## 6. Game controller mapping (extended gamepad: MFi, Xbox, PlayStation)

Names: Xbox / PlayStation. tvOS reserves the Home/Xbox/PS button.

### Recommended

| Control | Paged | Vertical | Book | Options/scrubber open |
| --- | --- | --- | --- | --- |
| D-pad | = remote arrows (turn, pan, bookmark/scrubber at edges) | = remote arrows | Turn | Focus |
| Left stick | Pan when zoomed / Fit Width; a flick left/right turns when nothing to pan | Analog scroll | Flick turns | Focus (system) |
| Right stick | Up/down = analog zoom; sideways pans | Analog scroll (fine) or auto-scroll speed while running | — | — |
| L3 / R3 (stick click) | R3 resets zoom | R3 jumps to top of chapter? (unused) | — | — |
| A / ✕ | = click: options (retry failed page first) | = click | Options | Pick |
| B / ○ | = Back (stack in section 5) | = Back | = Back | Back one layer |
| X / □ | Play: auto-advance | Play: auto-scroll | — | — |
| Y / △ | Bookmark | Bookmark | — | — |
| LB/RB, L1/R1 | Turn page | Previous/next page | Turn | Switch options tab |
| LT/RT, L2/R2 | Previous/next chapter | Previous/next chapter | Previous/next chapter | — |
| ☰ Menu / Options | Toggle reader options | Toggle options | Toggle options | Close |
| View / Share (Create) | Toggle HUD | Toggle HUD | Toggle HUD | — |
| PS touchpad tap / click | HUD / options (as remote tap / click) | same | same | — |

Notes:

- Today Y and View/Options both open the options. The recommendation moves the
  options to ☰ (the button games use for a pause menu, matching the HIG's
  "Back opens a pause menu" spirit) and frees Y for bookmarks. Some tvOS
  versions also deliver ☰ as a Menu press; if testing shows that, keep Y for
  options instead (D5).
- Analog zoom with the right stick is smooth and needs no hold gesture;
  analog triggers (L2/R2) are the alternative for zoom, but they are already
  the chapter buttons and an accidental chapter jump is costly.
- Sticks must keep the existing guard against tvOS also sending them as arrow
  presses (`stickRecentlyActive`).
- Siri Remote and a controller can be used together; the last input wins.

---

## 7. Decisions for John

| # | Decision | Recommended | Alternatives |
| --- | --- | --- | --- |
| D1 | Overall scheme | **A**: click = options, tap = HUD, Play/Pause = play | B (video app), C (click to zoom) |
| D2 | Where zoom lives (#17 vs #45 both use click) | **Hold Select** toggles zoom; Back zooms out | Click zooms and hold opens options (C); zoom only from the options |
| D3 | Play/Pause in paged mode | **Auto-advance pages** on a timer (speed in options), same "play" meaning as auto-scroll | Show/hide HUD; do nothing |
| D4 | Click while auto-scrolling (vertical) | **Open options** (which pauses auto-scroll) | Keep today's "first click stops, second opens" |
| D5 | Gamepad options button | **☰ Menu**, Y = bookmark | Keep Y/View for options (today) |
| D6 | Auto-scroll speed on a gamepad | **Right stick up/down** while running | L2/R2 while running |
| D7 | Should Back stop auto-scroll before closing the reader? | **Yes** (one extra press, no surprise exits mid-chapter) | No, Back always leaves once overlays are closed |
| D8 | HUD default | **On tap**, auto-hide 3 s; setting Always / On tap / Never | Show briefly on every page turn |
| D9 | Paged Down at the bottom of the page | **Page scrubber** | Show HUD; open options (today) |

---

## 8. Teaching the controls

John wants new users shown how to control the reader, with captions on a
sample manga, a way to replay it from Settings, and maybe a button legend
from the reader options. Today there is only the one-line first-use hint
from PR #45 (3 shows per mode) and the text table in Settings > Remote and
Controller.

### Sample content (hard rule)

Only real, human-made works with a clear licence that allows bundling. No
AI-made pages and no commercial manga. Code-drawn pages are for tests only.

| Candidate | Licence | Fits | Notes |
| --- | --- | --- | --- |
| **Pepper&Carrot** (David Revoy), a few pages of episode 1 | CC BY 4.0, commercial use allowed | Paged LTR; vertical by stacking the pages | Already in the Free Library catalog. Needs an attribution line in the tutorial and in Settings > About. Recommended. |
| National Diet Library manga from 1918 / 1927 (in `samples/LICENSES.md`) | Public domain (PDM) | Paged RTL, double page | Good for showing right-to-left. Old scans: check readability on a TV first. |
| Korean contest webtoons | CC, but AI status unverified, some NC/ND | Vertical | **Not usable** under the rule. |

Bundle about 6 to 8 pages at TV resolution (a few MB) so the tutorial works
offline and before any server is added; don't stream it.

### Options

| Option | What the user sees | Good | Weak |
| --- | --- | --- | --- |
| **A. Guided tutorial on a sample** | A short reader session on the bundled pages. Each step shows a remote drawing with the button lit and a caption ("Tap the touch surface to show the page number"), then waits for that input (Skip always works). Steps per mode: paged (turn, HUD, options, zoom, bookmark, Back), vertical (scroll, auto-scroll and speed, options), controller (only if one is connected). About 30 to 60 s. | Learn by doing, on a real page | Takes time; needs care to feel optional |
| **B. Coach marks on the user's own chapter** | The first time a mode opens, the same captions appear over the chapter they chose, one at a time, advancing as they try each one. | No sample needed; in context | Covers their page; can't show features that don't apply to that chapter (zoom on a vertical one) |
| **C. Button legend** | A full-screen overlay with a Siri Remote drawing (and a gamepad drawing when one is connected), each button labelled with what it does **in the current mode and state** (zoomed, auto-scrolling). Opened from a "Controls" button in the reader options header and from Settings. Back closes it. | Always available, quick to check, zero learning cost | Passive; people skim it |
| D. Text hint only (today, #45) | One line at the top for the first 3 opens | Cheap, already built | Easy to miss; can't show tap vs click |

### Recommendation: A + C

- **First open of the reader** (any mode): a small card "New to reading on Apple TV? Learn the controls (about 30 s)" with **Start** / **Not now**. Not now never asks again for that mode. Replaces the #45 text hint.
- **Onboarding** (first-run welcome, PR #43): an optional "Learn the controls" step that starts the same tutorial.
- **Replay:** Settings > Remote and Controller gets "Try the Controls" (tutorial) above the existing table, plus a per-mode picker.
- **Legend (C):** a "Controls" button in the reader options header, next to Bookmark and Pages. It shows the live legend for the mode you're in. On a controller, holding View also opens it.
- One source of truth: tutorial steps, legend labels, the Settings table and `docs/CONTROLS.md` all come from `ReaderControls` in MangaCore, so they can't drift from what the buttons do. A unit test checks every `ReaderInputAction` has a legend entry.
- Drawings: built in SwiftUI from SF Symbols (`appletvremote.gen4`, `gamecontroller`) and shapes, so no artwork to license. Show the remote generation the user holds when GameController can tell (it reports the Siri Remote model), otherwise the current silver remote.
- Accessibility: captions are real text (VoiceOver reads them); steps that wait for input also accept "Skip" via Play/Pause; Reduce Motion turns off the pulsing highlight.
- Tests: UI tests drive the tutorial with `-uiTesting` and the bundled sample; the legend's labels are checked per mode.

### Decisions to add

| # | Decision | Recommended | Alternatives |
| --- | --- | --- | --- |
| D10 | How to teach the controls | A + C: optional guided tutorial on a sample, plus a live legend from the reader options | B coach marks on the user's chapter; C only; keep D (today's hint) |
| D11 | When the tutorial is offered | On first reader open (Start / Not now card) and in onboarding; replay in Settings | Onboarding only; Settings only |
| D12 | Sample work | Pepper&Carrot (CC BY 4.0), bundled pages, credited | NDL public-domain manga for an RTL example too |

---

## 9. Revision after John's review (2026-11-26): one input per action

John pointed out duplicates: Play/Pause and Down both open the options,
a click stops auto-scroll although Play/Pause already does, and holding
Select also opens the options in vertical. He suggested either rotated
arrows per mode, or Play/Pause for auto-scroll / page turn in both modes
with a long Play/Pause press for the options.

### Holding a direction today

| Mode | Hold up/down | Hold left/right |
| --- | --- | --- |
| Vertical | Continuous scroll that speeds up the longer it is held | Nothing |
| Paged | Nothing (one turn per press) | Nothing |

Proposed addition: in paged mode, holding left/right flips pages with
increasing speed (like fast-forward), with the HUD page number showing until
release. It stops at the chapter edge (no automatic chapter change).

### John's two ideas, weighed

| Idea | Good | Problem |
| --- | --- | --- |
| Rotated arrows (paged: Up bookmark, L/R turn, Down options; vertical: Up/Down scroll, Left bookmark, Right options) | Paged half is today's layout; no hidden gestures | The options move to a different button after switching mode in the options; with zoom (#17) all four directions pan, so Down/Right can't also be options |
| Play/Pause = auto in both modes, hold Play/Pause = options | Play/Pause means the same thing everywhere | A long press hides the options again (what #45 fixed); every short Play/Pause has to wait for release |

### Revised recommendation (replaces section 4's table where they differ)

| Input | Paged | Vertical |
| --- | --- | --- |
| Click | Reader options (retries a failed page first) | Reader options (pauses auto-scroll) |
| Play/Pause | Start/stop page-turn timer | Start/stop auto-scroll |
| Tap | HUD | HUD |
| Hold Select | Zoom in/out | Nothing |
| Left/right | Turn page; hold = fast flip | Previous/next page |
| Up | Bookmark (pans first when zoomed) | Scroll; hold speeds up |
| Down | Page scrubber (pans first when zoomed) | Scroll; hold speeds up |
| Back | Close one layer (section 5) | Same |

Removed: Down and Play/Pause opening the options, click stopping
auto-scroll, hold Select opening the options in vertical. Bookmarking in
vertical: options header button, or Y on a controller.

---

## 10. Chosen scheme (John, 2026-11-26): Play/Pause plays, hold Play/Pause for options

| Input | Paged | Vertical | Book |
| --- | --- | --- | --- |
| Press Play/Pause | Start/stop page-turn timer | Start/stop auto-scroll | Nothing for now |
| **Hold Play/Pause (0.5 s)** | **Reader options** (stops the timer) | **Reader options** (stops auto-scroll) | **Reader options** |
| Click | Retry a failed page, else zoom in/out | Retry a failed page, else nothing (webtoon zoom later) | Nothing |
| Tap | HUD | HUD | HUD |
| Left/right | Turn page; hold = fast flip | Previous/next page | Turn page |
| Up | Bookmark (pans first when zoomed) | Scroll; hold speeds up | Nothing |
| Down | Page scrubber (pans first when zoomed) | Scroll; hold speeds up | Nothing |
| Back | Close one layer (section 5) | Same | Same |

Removed: Down, a click and holding Select opening the options; a click
stopping auto-scroll. Bookmark in vertical: options header or controller Y.

Implementation notes:

- SwiftUI's `onPlayPauseCommand` has no hold, so all three readers catch
  Play/Pause as raw presses (`pressesBegan`/`pressesEnded`, as the vertical
  reader already does) and decide on release: under 0.5 s = play, a hold
  fires the options at 0.5 s without waiting for release.
- Because the options sit behind a hold, discoverability matters more: the
  first-use hint becomes "Hold Play/Pause for options", the reader HUD shows
  the same line the first few times, and the tutorial and legend (section 8)
  start with it.
- Game controller: X = play, ☰ (or Y, D5) = options, A = click.
- PR #45 (click/hold Select = options) and the paged parts of #17 need
  adjusting to this; the implementing PR goes on top of them.

### HUD hint and legend placement (John, 2026-11-26)

- The tap HUD also shows a small corner hint: the Play/Pause glyph
  (SF Symbol `playpause.fill`) with "Hold for options". It shows and hides
  with the HUD.
- The button legend lives at the **bottom of the reader options** (below
  the settings rows, after scrolling down): "Controls" with a row per input
  for the current mode and state, built from `ReaderControls`. No separate
  Controls button in the options header.

### Auto-scroll and page-turn speed: named steps, no numbers (John, 2026-11-26)

Speed stays adjustable but is never shown or picked as a number. Five
named steps replace "Speed 3 of 10" in the options, the badge and the HUD:

| Step | Vertical auto-scroll (screens/s, from today's table) | Paged page-turn timer |
| --- | --- | --- |
| Very slow | 0.033 (level 1) | 30 s per page |
| Slow | 0.07 (level 3, today's default) | 20 s |
| Medium (default) | 0.12 (level 5) | 12 s |
| Fast | 0.2 (level 7) | 8 s |
| Very fast | 0.34 (level 9) | 5 s |

- Options row: the five names side by side, like the other option rows.
- While running, swipe/click up or down (vertical) and the controller's right
  stick move one step; the badge shows the name ("Auto-scroll · Fast").
- Saved per profile as before; a saved numeric level maps to the nearest
  step, so nobody's setting resets. Default stays at today's speed (Slow)
  if Medium proves too fast in testing.

### Game controller, final (John, 2026-11-26)

Works on full gamepads and on small controllers with no sticks or triggers
(8BitDo Micro-style reading remotes). The d-pad is navigation only.

| Button | Paged | Vertical | Options open |
| --- | --- | --- | --- |
| D-pad left/right | Turn page (pan first when zoomed) | Nothing | Focus |
| D-pad up/down | Pan when zoomed, else nothing | Scroll (hold speeds up); while auto-scrolling, one speed step | Focus |
| A (press) | Retry a failed page; when zoomed, zoom out | Retry a failed page | Pick |
| A (hold) | Zoom in | Nothing (webtoon zoom later) | — |
| B | Back (one layer) | Back | Back one layer |
| ☰ Menu | Reader options | Reader options | Close |
| Y | Bookmark | Bookmark | — |
| X | Start/stop page-turn timer | Start/stop auto-scroll | — |
| L1 / R1 | Previous / next chapter | Previous / next chapter | — |
| L2 / R2 | Unused for now | Unused | — |
| Sticks (if present) | Pan when zoomed | Analog scroll | Focus |
| View / Share | Show/hide HUD | Show/hide HUD | — |

Siri Remote matches: hold Select zooms in, a click zooms out, Back also
zooms out. A press arrives as Select, so remote and controller share code.

To verify when building: whether tvOS also delivers ☰ as a Back press on some
controllers (if so, use View for options there); L1/R1 jump straight to the
chapter's first page with a "Chapter 12" notice, not mirrored for
right-to-left.
