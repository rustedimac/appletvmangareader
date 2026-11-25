# Free Library

A built-in source that needs no setup: public-domain comics, pulp magazines
and illustrated books from the Internet Archive, plus the Pepper&Carrot
webcomic. A fresh install shows it on Home, and it doubles as App Review demo
content and the sample library for screenshots.

## How it works

- `MangaCore/FreeLibrary/catalog.json` is the curated list. The app ships a
  copy and, at most every 6 hours, fetches the newest one from this repo's
  `main` branch (`FreeLibrary.remoteCatalogURL`), so adding a title only takes
  a merged pull request. A fetched catalog is used only when it decodes, has
  `schema` 1, has no `problems`, and its `version` is at least the bundled one.
  It is saved in Caches.
- `FreeLibraryClient` implements `MangaServer`. Collections are the Library
  categories. Each catalog series is a series; each Internet Archive item in
  it is a chapter (a magazine run has one chapter per issue).
- Internet Archive pages come from the IIIF v3 manifest
  (`https://iiif.archive.org/iiif/3/<id>/manifest.json`), which gives every
  page's size up front. Images are `<service>/full/max/0/default.jpg`, or
  `full/pct:N` for scans wider than 2048 px. IIIF refuses any size larger than
  the source (`pct` over 100, `!w,h` that would upscale, a width over the
  real one), so the client never asks for one. Covers are
  `https://archive.org/services/img/<id>`.
- Pepper&Carrot episodes come from `https://www.peppercarrot.com/0_sources/episodes.json`
  (English only). Pages are `0_sources/<name>/low-res/en_Pepper-and-Carrot_by-David-Revoy_E<NN>P<PP>.jpg`,
  P00 being the title strip.
- Only https URLs on `archive.org` hosts and `www.peppercarrot.com` are ever
  built, and identifiers are checked, so a catalog entry can't point anywhere
  else.
- There is no account and no server progress. Progress is kept on the Apple
  TV per profile (`AppModel.syncsProgress` returns false). Series open left
  to right unless the profile saved its own settings for them.
- The Free Library is a normal `ServerConfig` with a fixed id
  (`FreeLibrary.serverID`, kind `.freeLibrary`), added at launch and kept after
  the user's own servers. Removing it in Settings sets
  `AppState.freeLibraryRemoved`, so it stays gone; "Add the Free Library"
  brings it back. It isn't in the Add Server picker (`ServerKind.userAddable`).

## Rules for catalog entries

1. **Internet Archive: US public domain only.** Published in the US in 1930
   or earlier (or published anywhere 1930 or earlier, for books first
   printed abroad). Set `license` to `publicDomainUS` and say why in `rights`.
   The app labels these "Public domain in the US".
2. **Never trust Internet Archive license fields or open search.** Items like
   Fables, Tintin and Berserk are tagged public domain there. Check the
   publication date of the scanned edition yourself.
3. Prefer scans of the original publication. Avoid scans of modern reprints
   (they can contain new copyrighted introductions or restorations): no
   `isbn_*` items, and skip the Taschen *Little Nemo* scans for that reason.
4. Avoid lending-library items (`bwb_*`, ids with `0000`, collections
   `inlibrary`, `printdisabled`, `lendinglibrary`): their IIIF manifests may not
   load.
5. No commercial manga, nothing AI-generated, and nothing that relies on a
   living franchise's trademarks (for example early Mickey Mouse or Tarzan
   strips, even where the strips themselves are public domain).
6. Pepper&Carrot is CC BY 4.0. Its credit (David Revoy, link, license) is
   shown in the series description and in Settings → Free Library → Credits.
   Keep it there.
7. Never change a series `id` (favorites and progress use it). Bump
   `version` on every edit and keep `problems` empty (`swift test` checks the
   bundled catalog).

## Current catalog (version 1, 2026-11-25)

Checked live through the IIIF manifests on 2026-11-25: every item loaded and
none has an access restriction.

| Collection | Series | Items |
| --- | --- | --- |
| Classic Comics | Dreams of the Rarebit Fiend (1905), Buster Brown (1904, 1910), Foxy Grandpa (1905, 1908), Bringing Up Father (1919, 1930) | 7 |
| Illustrated Books | Alice's Adventures in Wonderland (1867 printing), Through the Looking-Glass (1872), The Wonderful Wizard of Oz (1900), Peter Pan in Kensington Gardens (c. 1912), The Wind in the Willows (1913), The Red Fairy Book (1890), The Arabian Nights Entertainments (1898) | 7 |
| Pulp Magazines | Weird Tales, every issue March 1923 to December 1930; Amazing Stories, every monthly issue April 1926 to December 1930 | 87 + 57 |
| Webcomics | Pepper&Carrot (episode list fetched live) | 39 episodes |

A few fan scans of the magazines are missing an inside cover or a page; they
were the only scans of those issues.

## Not done yet

- EPUB/PDF items for the ebook reader: every Internet Archive book here also
  reads as page images, so nothing needs it today. When the PDF/ebook work
  lands, `.text` items can use IA's `_djvu.txt` with `BookProviding`.
- Pepper&Carrot in other languages (the site has 60+); the reader uses English.
- A "Continue Reading" row for the Free Library itself (progress is local).
