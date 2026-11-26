# Servers: what's supported and what to add next

The app reads from self-hosted servers through `MangaServer`
(`Packages/MangaCore/Sources/MangaCore/Networking/MangaServer.swift`). This page
lists the server types the app supports today and ranks other services
worth supporting, with a rough effort and value for each.

## Supported

| Type | How | Progress | Notes |
| --- | --- | --- | --- |
| **Kavita** | Native REST client | Synced per Kavita user | Page sizes up front, so spreads pair before loading. |
| **Suwayomi** (Tachiyomi/Mihon server) | Native GraphQL client | One progress per server (per-user only in previews) | Library only, no source browsing. |
| **Komga** | Native REST client (`KomgaClient`, Komga 1.19+) | Synced per Komga user | API key or email + password. Libraries, series, books, page sizes, new/updated rows, Continue Reading from books in progress. |
| **OPDS 1.2 / 2.0** | Generic client (`OPDSClient`) | Kept on the Apple TV | Covers every server below that has an OPDS feed. Page streaming via OPDS-PSE or OPDS 2 DiViNa manifests; otherwise CBZ files are downloaded and unpacked locally. |

### Reading lists, collections and smart filters

`MangaServer.collectionSupport` says which of these a server can list; the
Library bar shows a button for each (`ServerCollectionsView`). Read-only:
the app never creates, edits or reorders them.

| Server | Reading lists | Collections | Smart filters |
| --- | --- | --- | --- |
| Kavita | `POST api/ReadingList/lists`, items from `GET api/ReadingList/items` | `GET api/Collection`, series from `GET api/Series/series-by-collection` | `GET api/filter` (series filters only), `POST api/filter/decode`, then `POST api/Series/all-v2` |
| Others | none yet | none yet (Komga has collections, a possible follow-up) | none |

Kavita applies the user's library access and age rating. The profile's
library pick is applied on top: a scoped collection, or a smart filter whose
statements are combined with Or, loads in one request and is narrowed in the
app; an And filter gets a library statement added. A reading list opens each
chapter in its own series; reading on past the chapter follows the series,
not the list (follow-up). Wrapper servers must forward
`collectionSupport`, `collections(_:)`, `series(in:page:pageSize:)` (the
`ServerCollection` one) and `readingListEntries(_:)`.

### What the OPDS type covers

Enter the catalog URL, or just the host: the client tries
`/opds/v1.2/catalog`, `/opds`, `/opds-comics`, `/opds/v1.2`, `/opds/v2/catalog`,
`/opds/v2.0/catalog` and `/opds/v2.0` (`OPDSClient.catalogPaths`).

| Server | OPDS path | Streams pages? | Tested |
| --- | --- | --- | --- |
| Komga | `/opds/v1.2/catalog`, `/opds/v2/catalog` | Yes (PSE, DiViNa) | Live against Komga 1.30.2 (v1.2 and v2) |
| Stump | `/opds/v1.2/catalog`, `/opds/v2.0/catalog` | v1.2: PSE. v2: downloads the CBZ | Live against Stump (v1.2 and v2) |
| Kavita | `/api/opds/<api key>` | Yes (PSE) | Use the native Kavita type instead |
| Codex | `/opds/v1.2/`, `/opds/v2.0/` | Yes (PSE) | Paths from Codex docs; not run live yet |
| Ubooquity | `/opds-comics/`, `/opds-books/` | Comics: PSE | From Ubooquity docs; not run live yet |
| Calibre-Web | `/opds` | No: downloads the file | Fixture in Calibre-Web's feed format |
| Calibre content server | `/opds` | No: downloads the file | Not run live yet |

Limits today: PDF and EPUB files from OPDS catalogs don't open yet (they
will once the PDF/ebook reader lands), CBR/RAR archives aren't supported,
and OPDS has no standard way to write progress back.

## Worth adding next, ranked

Value weighs how many people run the server and whether the OPDS type
already serves them. Effort is for a native client at the level of the
Kavita and Komga ones, with fixtures and UI tests.

| # | Service | Value | Effort | Why |
| --- | --- | --- | --- | --- |
| 1 | **PDF/EPUB from OPDS** (not a server) | High | Small | Calibre-Web and Calibre users mostly have EPUB/PDF. Hook `OPDSClient.pages` up to the PDF and book readers once they merge. |
| 2 | **Codex** native | Medium | Medium | Popular with comic readers and has a REST API with per-user progress and filters. OPDS already works, so a native client mainly adds progress sync. |
| 3 | **Stump** native | Medium | Medium | Young but growing; GraphQL and REST APIs with per-user progress. OPDS already works. |
| 4 | **Plain folders over WebDAV or SMB** (NAS shares of CBZ/PDF/EPUB) | High | Large | Many people have no server at all, just a NAS. WebDAV is plain HTTP (doable with `URLSession`); SMB needs a library such as AMSMB2. Folder names become series; files become chapters; CBZ pages unpack through `LocalArchiveCache`. Progress stays local. |
| 5 | **Calibre content server** native (`/ajax` API) | Medium | Medium | Huge user base for ebooks, but mostly EPUB, so it depends on the book reader. OPDS covers browsing today. |
| 6 | **Audiobookshelf** (ebooks only) | Low to medium | Medium | Mainly audiobooks and podcasts; its ebook support (EPUB/PDF/CBZ) is secondary. Only worth it after the book reader, and only for its ebook libraries. |
| 7 | **Ubooquity** | Low | Small | Older and little maintained. OPDS covers it fully. |
| 8 | **Komga OPDS-only users** | None | None | Covered by the native Komga type. |

Recommendation: do 1 first (small, unlocks Calibre-Web/Calibre), then 4
(the biggest group not served at all), then native Codex and Stump only if
users ask for progress sync on them.

## Testing without the real servers

Komga and Stump run in Docker in the cloud container (`mirror.gcr.io/gotson/komga`,
`mirror.gcr.io/aaronleopold/stump`), loaded with code-drawn test pages.
`KomgaLiveTests` and `OPDSLiveTests` run the clients end to end against any
server when these are set:

```sh
KOMGA_LIVE_URL=http://localhost:25600 KOMGA_LIVE_API_KEY=… swift test --filter KomgaLiveTests
OPDS_LIVE_URL=http://localhost:10801 OPDS_LIVE_USER=… OPDS_LIVE_PASSWORD=… swift test --filter OPDSLiveTests
```

UI tests use in-memory servers instead: `-uiTesting -mockKomga`
(`MockKomgaTransport`) and `-uiTesting -mockOPDS` (`MockOPDSTransport`).
