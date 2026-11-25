# Remote and controller button map

The same map is in the app under **Settings > Remote and Controller**, built
from `ReaderControls` in MangaCore, so change both together.

The scheme follows tvOS's own media apps: a click brings up the controls,
Play/Pause plays, Menu goes back. **In every reader a click or holding Select
opens the reader options**, so they are always one press away. Play/Pause
opens them too in the page and book readers; in the vertical reader it starts
and stops auto-scroll instead. The first few times each reader mode opens, a
hint at the top of the screen says this.

## Page reader

| Siri Remote | Does |
| --- | --- |
| Click, or hold Select | Reader options |
| Play/Pause | Reader options |
| Swipe or click down | Reader options |
| Swipe or click left / right | Turn the page (follows the reading direction) |
| Swipe or click up | Bookmark the page, or remove the bookmark |
| Menu (Back) | Close the options, then close the reader |

## Vertical (webtoon) reader

| Siri Remote | Does |
| --- | --- |
| Click, or hold Select | Reader options. While auto-scroll runs, a click stops it (click again for the options) and holding Select opens the options straight away. |
| Play/Pause | Start or stop auto-scroll |
| Swipe up / down | Scroll, with momentum. While auto-scrolling: faster / slower. |
| Click up / down | Scroll a step; hold to keep scrolling. While auto-scrolling: faster / slower. |
| Click left / right | Previous / next page |
| Menu (Back) | Close the options, then close the reader |

The reader options also have **Start Auto-scroll** and the speed.

## Book reader (EPUB and text)

| Siri Remote | Does |
| --- | --- |
| Click, or hold Select | Reader options |
| Play/Pause, or swipe / click down | Reader options |
| Swipe or click left / right | Turn the page |
| Menu (Back) | Close the options, then close the book |

## Game controller (Xbox, PlayStation, MFi)

| Button | Does |
| --- | --- |
| Y, or Options / View / Share | Reader options (open and close) |
| A | Same as a click |
| B | Same as Menu (Back) |
| D-pad | Same as the remote's arrows |
| L1 / R1 (LB / RB) | Turn the page left / right |
| L2 / R2 (LT / RT) | Previous / next chapter |
| X | Start or stop auto-scroll (vertical reader) |
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
