# Reading progress sync

How Kavita, Suwayomi and Tachiyomi/Mihon keep reading progress, and what
this app does with it. Checked against Kavita `develop` (0.9.1.24) and
Suwayomi-Server `master` (November 2026), from source.

## Kavita

Kavita has real user accounts, and all reading state belongs to a user.

**Signing in**

| Endpoint | What it does |
| --- | --- |
| `POST api/Account/login` `{username, password}` | Returns `UserDto`: `username`, `token` (JWT), `refreshToken`, `apiKey` (the user's OPDS auth key) and `authKeys` (every auth key on the account). |
| `POST api/Account/refresh-token` `{token, refreshToken}` | New JWT. |
| `POST api/Plugin/authenticate?apiKey=&pluginName=` | Exchanges an auth key for a JWT. What third-party clients (Tachiyomi extension, Paperback) use. |
| `POST api/Account/create-auth-key` `{name, keyLength, expiresUtc?}` | Creates a named auth key for the signed-in user (not for read-only users). |
| Any endpoint with header `x-api-key: <auth key>` (or `?apiKey=`) | Authenticated as the key's owner. No JWT needed. |

- An auth key (the OPDS key included) belongs to exactly one user. Whoever
  holds it reads as that user, with that user's library access and progress.
- The JWT lives 3 days. The refresh token lives 30 days, but **a user has
  only one refresh token**: every login, refresh or `Plugin/authenticate`
  replaces it. A client that logs in through those endpoints quietly
  invalidates the refresh token of the user's web browser session.
- Kavita 0.9 auth keys can expire (the OPDS key on the test server has an
  expiry). Keys made with `create-auth-key` and no `expiresUtc` don't.

**Progress**

| Endpoint | What it does |
| --- | --- |
| `POST api/Reader/progress` `ProgressDto {chapterId, pageNum, volumeId, seriesId, libraryId}` | Saves progress. The server looks up the volume, series and library from the chapter itself, so only `chapterId` and `pageNum` matter. `pageNum` is capped at the page count; `pageNum >= pages` means the chapter is read. Page 0 with no existing record is ignored. |
| `GET api/Reader/get-progress?chapterId=` | `pageNum` and `lastModifiedUtc` for one chapter. |
| `GET api/Reader/continue-point?seriesId=` | The chapter to resume: the first chapter if nothing is read, else the one in progress, else the one after the last chapter with progress. |
| `GET api/Series/volumes?seriesId=` | Every chapter's `pagesRead`, `pages` and `lastReadingProgressUtc` for the signed-in user. |
| `POST api/Series/on-deck` | "On Deck": series with progress in the last 30 days that aren't finished (both windows are per-user preferences now). The web UI's Continue Reading row. |
| `POST api/Reader/mark-read`, `mark-unread`, `mark-multiple-read`, `mark-multiple-unread` | Whole series or a set of chapters. |
| `GET api/Tachiyomi/latest-chapter`, `POST api/Tachiyomi/mark-chapter-until-as-read` | What Mihon's Kavita tracker uses: a "read up to chapter N" number, not page positions. |

Kavita also has KOReader and Panels sync endpoints, which are for those apps.

## Suwayomi (and Tachiyomi / Mihon)

**Mihon / Tachiyomi** keep progress in the app's own database (`last_page_read`,
`read`, history with `last_read`). Nothing goes to a server by default.
"Trackers" (AniList, MyAnimeList, Kitsu, MangaUpdates, ...) only receive a
"last chapter read" number. Kavita, Komga and Suwayomi are "enhanced trackers"
in Mihon: they mark chapters read on the server up to that number. None of
this carries page positions.

**Suwayomi-Server** stores `isRead`, `lastPageRead` (zero-based) and
`lastReadAt` (epoch seconds) on each chapter, readable through GraphQL and
written with `updateChapter(s)(input: {id(s), patch: {isRead, lastPageRead}})`,
which also sets `lastReadAt`. The server's own trackers and KOReader sync
hang off those writes.

Auth modes (`authMode` setting):

| Mode | Who you are |
| --- | --- |
| `NONE` | Everyone is user 1. |
| `BASIC_AUTH` (deprecated) | HTTP basic auth with the one configured username/password. Still user 1. |
| `SIMPLE_LOGIN` | Cookie session from the web login form. User 1. |
| `UI_LOGIN` | `mutation login(input: {username, password}) { accessToken refreshToken }`, then `Authorization: Bearer <accessToken>` (images accept the header or `?token=`). `refreshToken(input: {refreshToken})` gives a new access token. |

In every released version there is one progress per server, shared by
everyone who connects. Suwayomi's unreleased preview adds real **user
accounts**: chapter read state moves to a per-user `ChapterUser` table,
`register` creates users and `query { user { id username } }` returns the
signed-in user. Only `UI_LOGIN` maps a login to a user.

## What this app does

**Kavita: each profile signs in as its own Kavita user.**
- Sign in with username and password. The app calls `api/Account/login`
  once, then reuses (or creates) an auth key named "Apple TV Manga Reader"
  with no expiry and keeps only that key and the username, in the Keychain.
  The password is never stored. If the account may not create keys
  (read-only users) the app falls back to the account's OPDS key.
- Pasting an OPDS URL or API key still works, as before.
- Every API call sends `x-api-key`, so the app never touches the user's
  refresh token and doesn't log their browser out. Servers too old for
  `x-api-key` fall back to `Plugin/authenticate` and a JWT.
- Images keep using `?apiKey=` in the URL.

**Suwayomi: shared progress, with per-user login where the server has it.**
- With a username and password the app first tries `login`
  (`UI_LOGIN`, Bearer tokens, refreshed or re-logged in on 401) and uses
  basic auth when that isn't available.
- If the server answers `user { username }` it has user accounts, and every
  profile signed in as its own user syncs to it.
- Otherwise the existing rule stands: one profile syncs (the one that added
  the server) and the others keep progress on the Apple TV.

**Sync rules (all servers)**
- Pull: series detail and Continue Reading come from the server for
  profiles that sync. Each chapter carries `lastReadAt` (Kavita
  `lastReadingProgressUtc`, Suwayomi `lastReadAt`).
- Push: every page settle, chapter change and reader close writes local
  progress first, then the server. A failed push stays queued on the
  series (`SeriesProgress.pending`) and is retried the next time the series
  or Home loads, after a backoff (5 s, 10 s, 20 s, ... up to every 5
  minutes) while the app runs, and as soon as the app returns to the
  foreground.
- Conflicts: latest wins, per chapter. A queued local change is pushed only
  if it is newer than the server's `lastReadAt` for that chapter;
  otherwise the server's state wins and the queued change is dropped.
  Marking chapters or a series unread drops their queued changes, so an
  old push can't mark them read again.
- Resume point: the in-progress chapter read most recently, else the first
  unread chapter after the last one read (Kavita's continue-point rule),
  else the first chapter.
- Profiles that don't sync get their own Continue Reading row on Home, from
  local progress.

## Posters after reading

Home rows, library grids, Favorites and Search keep the summaries they
loaded, so their badges and bars would stay at the old progress. When the
reader closes it calls `AppModel.refreshSeriesProgress`, which waits for the
series' progress saves (`startRecordingProgress` registers each save before
returning and chains saves per series in order), reloads the series through
`seriesDetail` (local and queued progress resolved for the profile) and
stores a `SeriesProgressOverride` per profile and series. `SeriesPoster`
applies it with `withCurrentProgress`. Opening series detail records one
too, and "Mark as Unread" uses the same path. Series detail reloads after
the reader only once those saves land, so the server never answers with the
old page.
