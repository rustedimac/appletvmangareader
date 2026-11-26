# Testing on a real Apple TV

A checklist for trying a build on the Apple TV at home. Browsing, both
readers, the menu, profiles and progress sync were checked in the tvOS
simulator against the real Kavita and Suwayomi servers. Items marked
**(device)** can only be judged on real hardware (remote feel, focus effects,
sharpness, memory).

## Install

1. On the Mac: `xcodegen generate`, then open `MangaReader.xcodeproj`.
2. Select the **MangaReader** target → Signing & Capabilities → pick your team.
3. Pair the Apple TV: on the TV, Settings → Remotes and Devices → Remote App
   and Devices; in Xcode, Window → Devices and Simulators → pair it.
4. Pick the Apple TV as the run destination and press Run.
5. The first launch asks for Local Network access. Allow it, or the servers
   won't load.

## First run and servers

- [ ] With no servers, Home says "No servers yet".
- [ ] Settings → Add Server → Kavita: paste the OPDS URL with the iPhone
      keyboard (Continuity Keyboard). The field keeps what you pasted while
      you type; on Return, Test Connection or Save it splits into the address
      and the API key (dots).
- [ ] Type just the address (e.g. `http://kavita.local:5000`) and the key
      separately. Test Connection passes. A wrong host says "Couldn't reach",
      a wrong key says "rejected the API key".
- [ ] In the simulator (no paste), launch a Debug build with
      `-serverEditorPrefill "kavita|http://<host>/api/opds/<key>"` to try the
      pasted-URL path. Use a fake key in anything you commit.
- [ ] Test Connection shows a green check.
- [ ] Add Suwayomi with its address only. Test Connection passes.
- [ ] Both servers appear on Home within a few seconds.

## Profiles

- [ ] Settings → Manage Profiles → add a second profile with a different avatar.
- [ ] Relaunch the app: the "Who's reading?" picker shows, centered.
- [ ] As the new profile, Home shows "<name> isn't signed in to Kavita" until a
      key is added for that profile. Suwayomi works without one.
- [ ] Favorites and Continue Reading differ between profiles.

## Browsing

- [ ] Home: Favorites (once you add one), then per server Continue Reading,
      Recently Updated, Newly Added. Covers load.
- [ ] Library → Kavita → each library opens a poster grid.
- [ ] Library → Suwayomi → categories show as chips. A large category (KR,
      700+) keeps loading as you scroll down, without stalls.
- [ ] Search: type a title. Results group by server.
- [ ] Series page: synopsis, genres, read state per chapter, Continue button
      on one line.
- [ ] Favorite / Favorited toggles, and the series shows in the Favorites tab
      and the Home row.
- [ ] Back (Menu button) returns to the same poster you left. **(device)**
- [ ] Posters lift and tilt with the focus effect; it feels smooth. **(device)**

## Two-page reader

Use a Kavita manga with a two-page color spread (many chapters end on one).

- [ ] Start Reading opens full screen. The first page is alone (cover).
- [ ] Left click / swipe left goes forward in right-to-left books.
- [ ] Pairs read right page first, then left.
- [ ] A spread split across two files lines up with no gap or line at the spine.
- [ ] A wide (landscape) page shows alone.
- [ ] If pairs come out wrong, Play/Pause → "Pages paired wrong? Shift by one"
      fixes them and stays on the same page.
- [ ] Past the last page, a card names the next chapter; one more press opens it.
- [ ] Turning pages is instant once the reader has preloaded. **(device)**
- [ ] Text is sharp on a 4K TV, not soft or blocky. **(device)**

## Vertical (webtoon) reader

Use a Suwayomi webtoon (KR category).

- [ ] Play/Pause → Reading Mode → Vertical Scroll switches in place.
- [ ] Swiping on the touch surface scrolls smoothly; click down moves about one
      screen. **(device)**
- [ ] Holding down scrolls continuously and speeds up. **(device)**
- [ ] Page joins are invisible: no gap, line or jump as pages load.
- [ ] Reaching the end flows into the next chapter with a small divider.
- [ ] Column width in the menu changes the width live.
- [ ] A 100+ page chapter stays smooth with no memory warning or crash after
      a few minutes of scrolling. **(device)**

## Reader menu

- [ ] Swipe down or Play/Pause opens the drawer on the right; the page stays
      visible behind it.
- [ ] Every setting applies immediately.
- [ ] Settings are remembered per series (leave and reopen).
- [ ] Set as Default makes new series open that way.
- [ ] Chapters tab jumps to another chapter.
- [ ] Menu or Play/Pause closes the drawer.

## Progress sync

- [ ] Read a few pages of a Kavita chapter, leave the reader, and check the
      Kavita web UI: the chapter shows the same page.
- [ ] Finish a chapter: Kavita marks it read; Home's Continue Reading updates.
- [ ] Suwayomi: same check in the Suwayomi web UI (only for the profile that
      syncs to it; others keep progress on the Apple TV).
- [ ] Quit the app mid-chapter (double-click TV button, swipe up): reopening
      continues from the same page.

## Home screen

- [ ] The app icon shows the layered parallax effect when focused. **(device)**
- [ ] With the app in the top row, the Top Shelf shows the banner image.
- [ ] Note: the icon and Top Shelf art are simple placeholders; replace the
      files under `App/Resources/Assets.xcassets` (or edit
      `tools/make_brand_assets.py`) with final artwork.

## Report back

For anything that fails, note the server, series, chapter and page, and
which remote you used (Siri Remote generation or the iPhone remote).
