# Remote and controller button map

The same map is in the app under **Settings > Remote and Controller**, built
from `ReaderControls` in MangaCore, so change both together.

The scheme John chose is in docs/READER_CONTROLS.md section 10. One input
does one thing: **holding Play/Pause (half a second) opens the reader
options in every reader**, deliberately not one easy press away. A
Play/Pause press plays: auto-scroll in the vertical reader, a page-turn timer
in the page reader. A light tap on the touch surface (not a click) shows the
page number for a few seconds, with a "Hold for options" hint in the corner.
Menu (Back) closes one thing at a time before it closes the reader. The first
few times each reader mode opens, a hint at the top of the screen says this,
and the same list is at the bottom of the reader options under **Controls**.

**Tutorial.** The first time a reader opens, the app offers a short
controls tutorial on a bundled sample comic (Pepper&Carrot episode 1, CC BY
4.0, see docs/TUTORIAL_SAMPLE.md). Each step names one input with a caption
and moves on when it's done; Menu leaves it. Replay it from Settings >
Remote and Controller > Learn the Controls. Steps: `ReaderTutorial.steps(for:)`.

Speeds (auto-scroll and the page timer) are named steps, never numbers:
Very Slow, Slow (the default), Medium, Fast, Very Fast.

## Page reader

| Siri Remote | Does |
| --- | --- |
| Hold Play/Pause | Reader options |
| Play/Pause | Turn pages on a timer (start or stop) |
| Tap the touch surface | Show the page number |
| Swipe or click left / right | Turn the page (follows the reading direction); pans first when zoomed |
| Swipe or click up | Bookmark the page, or remove the bookmark (pans up first when zoomed) |
| Swipe or click down | Page thumbnails (pans down first when zoomed) |
| Hold Select | Zoom in |
| Click | Zoom out (retries a page that didn't load) |
| Menu (Back) | Close the options or thumbnails, hide the page number, zoom out, stop the timer, then close the reader |

## Vertical (webtoon) reader

| Siri Remote | Does |
| --- | --- |
| Hold Play/Pause | Reader options (stops auto-scroll) |
| Play/Pause | Start or stop auto-scroll |
| Tap the touch surface | Show the page number |
| Swipe up / down | Scroll, with momentum. While auto-scrolling: faster / slower. |
| Click up / down | Scroll a step; hold to keep scrolling. While auto-scrolling: faster / slower. |
| Click left / right | Previous / next page |
| Click | Retry a page that didn't load |
| Menu (Back) | Close the options, hide the page number, stop auto-scroll, then close the reader |

The reader options also have **Start** and the speed for auto-scroll (vertical)
and the page timer (page reader).

## Book reader (EPUB and text)

| Siri Remote | Does |
| --- | --- |
| Hold Play/Pause | Reader options |
| Swipe or click left / right | Turn the page |
| Menu (Back) | Close the options, then close the book |

## Game controller (Xbox, PlayStation, MFi, 8BitDo)

The d-pad only navigates, like the remote's arrows; other actions have their
own buttons. Nothing needs L2 / R2, so small controllers work fully.

| Button | Does |
| --- | --- |
| ☰ Menu / Options / Start | Reader options (open and close) |
| D-pad | Navigate: turn pages (page reader, left / right) or scroll (vertical reader, up / down) |
| A | Same as a click; hold to zoom in, press again to zoom out |
| B | Same as Menu (Back) |
| Y | Bookmark the page |
| X | Auto-scroll, or the page timer |
| L1 / R1 (LB / RB) | Previous / next chapter |
| View / Share / Select | Show the page number |
| Either stick | Scroll smoothly (vertical reader) |

Mapping code: `GamepadMapping` and `GamepadStick` in
`Packages/MangaCore/Sources/MangaCore/Reader/ReaderInput.swift`.

## Chapter list (series page)

| Siri Remote | Does |
| --- | --- |
| Click a chapter | Read it |
| Move right to **…**, then click | Mark as Read, Mark as Unread, Mark Previous as Read, Mark Series as Unread |
| Hold Select on a chapter | The same items |
| **More** (top of the page) | Mark Series as Read / Unread |

## Simulator

In the tvOS Simulator, Return is a click and the arrow keys are the remote's
arrows. A long press is holding Return (or holding the click on the
Simulator's on-screen remote). Some simulator viewers can't hold a key, which
is why every long-press action also has a button.
