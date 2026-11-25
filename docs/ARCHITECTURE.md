# Architecture

## Layout

| Path | What lives there |
| --- | --- |
| `Packages/MangaCore` | Swift package with all non-UI logic. No SwiftUI. Tested with `swift test`. |
| `MangaCore/Models` | Shared value types: `ServerConfig`, `Profile`, `SeriesSummary`, `SeriesDetail`, `Chapter`, `PageDescriptor`, `HomeFeed`. |
| `MangaCore/Networking` | `HTTPClient`, `HTTPTransport` (mockable), and the `MangaServer` protocol every backend implements. |
| `MangaCore/Kavita` | `KavitaClient` (REST, API key → JWT via `api/Plugin/authenticate`) and `KavitaOPDS` URL parsing. |
| `MangaCore/Suwayomi` | `SuwayomiClient` (GraphQL at `/api/graphql`, optional basic auth). |
| `MangaCore/Storage` | `AppState` (profiles, servers, per-profile favorites / progress / reader settings), `StateStore` (UserDefaults JSON), `SecretStore` (Keychain). |
| `MangaCore/Reader` | `ReaderSettings` and `SpreadLayout`, the two-page pairing logic. |
| `App/Sources/Shared` | `AppModel`, the `@Observable` app model in the SwiftUI environment, plus shared views. |
| `App/Sources/<Tab>` | One folder per tab: Home, Library, Favorites, Search, Settings. |
| `App/Sources/Reader` | Paged and webtoon readers. |
| `App/UITests` | XCUITest UI tests. Launch with `-uiTesting` for in-memory state. |

## Rules of the road

- **UI never talks to Kavita or Suwayomi directly.** It calls `MangaServer`
  through `AppModel.client(for:)`. New backend capabilities go on the protocol
  first, with an implementation and tests for both clients.
- **All persisted changes go through `AppModel.update { }`**, which mutates
  `AppState` and saves it. Add new persisted fields to `AppState` /
  `ProfileData` with tests in `AppStateTests`.
- **Secrets never go in `AppState`.** Credentials are per profile, per server,
  in the Keychain.
- **tvOS storage is small.** Only UserDefaults (~1 MB) and the Keychain
  persist. Caches may be purged at any time. Keep `AppState` compact.
- **Profiles.** Favorites, local progress and reader settings belong to a
  profile. Kavita progress syncs to that profile's Kavita user. Suwayomi has
  one progress per server, so by default only the profile that added the
  server syncs there and others keep progress locally
  (`ProfileServerSettings.syncProgressToServer`).

## Server API notes (verified against Kavita 0.9.1 and Suwayomi 2.4)

Kavita
- Login: `POST api/Plugin/authenticate?apiKey=…&pluginName=…` → `{ token }`, used as `Authorization: Bearer`.
- Images take `?apiKey=` and need no Bearer header: `api/Reader/image`, `api/Image/series-cover`.
- `api/Reader/file-dimensions?chapterId=` gives every page's width/height up front, so spreads are known before loading.
- List endpoints return a JSON `Pagination` response header, e.g.
  `{"currentPage":1,"itemsPerPage":2,"totalItems":179,"totalPages":90}`. `hasMore` is `currentPage < totalPages`.
- `file-dimensions` entries carry `isWide`; on the live server it always matched width > height. `PageSize.wideOverride` keeps it only when it disagrees.
- Collections: `GET api/Collection` (filter field 7 in `Series/v2`). They show up as extra categories with `kind == .collection` and ids prefixed `collection-`.
- Chapters inside a volume are not sorted; sort by `sortOrder`. `titleName` is the display name ("Vol.1 Ch.1"), `title` is just the number.

Suwayomi
- No auth by default. `orderBy`/`orderByType` work (deprecated in favor of `order: [{by, byType}]`).
- `category.mangas` and `manga.chapters` take no arguments and return everything (a category can hold 700+). Page with the top-level `mangas(condition: {categoryIds: [id]}, first:, offset:)`, and list chapters with `chapters(condition: {mangaId:}, orderBy: SOURCE_ORDER, orderByType: ASC)` (ascending = oldest first).
- Category 0 is "Default" (manga in no other category). It is hidden when empty, and `categoryIds: [0]` matches nothing, so it is paged client-side.
- `chapterNumber` is -1 when the source gave no number (hundreds of chapters on the live server). Never sort by chapter id.
- Timestamps are strings: `lastReadAt` / `fetchedAt` in seconds, `uploadDate` in milliseconds.
- `pageCount` is `-1` until `fetchChapterPages` runs. Page sizes are only known after an image downloads.
- `UpdateChapterPatchInput` fields: `isBookmarked`, `isRead`, `lastPageRead`.

## Double-page spreads

`SpreadLayout` pairs pages. Wide images are always alone; pairing restarts
after one. The first page is alone by default (cover). `shiftPairing` flips the
parity of the first run when a chapter's pairs come out wrong. Unknown sizes
count as tall; the reader re-lays out when sizes arrive and keeps the current
page on screen. See `SpreadLayoutTests` for the exact rules.
