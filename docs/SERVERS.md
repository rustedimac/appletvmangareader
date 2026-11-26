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

## Several addresses per server

A server can have more than one address, e.g. `http://192.168.1.10:5000` at
home and `https://manga.example.com` through a reverse proxy or tunnel when
the Apple TV is elsewhere. Add them in the server editor under **Other
Addresses**; clear a field to remove it.

- The app uses the **first address in the list that answers**. On the first
  request of a launch (and again every 10 minutes, or as soon as the address
  in use stops answering) it checks every address at once with a plain GET
  of the address, 5 seconds each. Any HTTP answer counts, even a 401: the
  check only asks "is this the way in?".
- Clients always build URLs from the main address (`ServerConfig.baseURL`).
  `FailoverTransport` (added by `MangaServerFactory.make` when a server has
  more than one address) rewrites each request to the chosen address and,
  when a request can't connect, checks again and retries once on the next
  one. `MangaServer.imageRequest` rewrites covers and pages the same way.
  URLs a server hands out with one of its other addresses (OPDS links) are
  rewritten too.
- The chosen address per server is remembered in UserDefaults
  (`mangareader.serverAddresses.lastGood`), so images go to the right place
  right after launch. That memory is per device and isn't synced.
- When none answers, the error says so in plain words
  (`MangaError.unreachable`); other network errors go through
  `ConnectionErrorText` instead of raw `NSURLErrorDomain` codes.
- The addresses are part of the server record, so they sync through iCloud
  and Wi‑Fi backups with the server (no new `SyncMapper` domain: same
  `server/<id>` record, one more field, written only when there are extra
  addresses so older builds read the same JSON). An older build that edits
  the server would drop the extra addresses.

## Set up from your phone

**Set Up from Your Phone**, under the login in the server editor, opens a screen
with a QR code. While it's open, the Apple TV serves a small form at
`http://<tv-address>:8791/<six-digit code>/` (code new on every visit, any
other path is a 404). The phone fills in type, name, addresses and the
login, and **Send** fills the Apple TV's form and starts a connection test.
Nothing is saved until the user presses Add Server or Save on the TV, and
nothing leaves the local network. The page never shows a saved key or
password. Code: `MangaCore/Pairing/PhoneSetup.swift` (shares
`LocalHTTPServer` with the Wi‑Fi backup), `App/Sources/Settings/PhoneSetupView.swift`.

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
