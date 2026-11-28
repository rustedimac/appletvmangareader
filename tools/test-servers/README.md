# Local test servers

A set of self-hosted servers for running the live tests in
`Packages/MangaCore/Tests/MangaCoreTests/*LiveTests.swift` and for pointing
the simulators at. It runs on macOS (Apple Silicon) with no Docker and no
system-wide installs. Everything lives in one folder, `$TEST_SERVERS_DIR`,
which defaults to `~/test-servers`.

```
tools/test-servers/start.sh    # starts every installed server (safe to re-run)
tools/test-servers/status.sh   # up/down per server (any HTTP answer counts as up)
tools/test-servers/stop.sh     # stops them (by listening port)
```

The servers run under `nohup` and keep going after the shell exits. They
don't come back after a reboot, so run `start.sh` again then.
Logs go to `$TEST_SERVERS_DIR/logs/<name>.log`.

Every server binds to 0.0.0.0, so the Apple TV, iPhone and iPad simulators
(and real devices on the LAN) can reach it at the Mac's IP. Ports 5000 and
7000 are left alone: macOS AirPlay Receiver uses them.

Test login everywhere: **tester / mangatest1** (Komga: `tester@example.com`).
Suwayomi has no login. API keys are created per install. Keep them in
`$TEST_SERVERS_DIR/secrets.txt` and never commit them.

## Servers

| Server | Version tested | Port | What the app uses |
| --- | --- | --- | --- |
| Komga | 1.30.2 | 25600 | REST `/api/v1`, OPDS `/opds/v1.2/catalog`, `/opds/v2/catalog` |
| Kavita | 0.9.1.4 | 5005 | REST `/api`, OPDS `/api/opds/<opds auth key>` |
| Suwayomi-Server | v2.4.2373 | 4567 | GraphQL `/api/graphql` (local source only) |
| Stump | 0.1.14 | 10801 | OPDS `/opds/v1.2/catalog`, `/opds/v2.0/catalog` (or just the host) |
| calibre content server | 9.19 | 8080 | `/ajax/*`, OPDS `/opds`; Digest login; library id `library` |
| Calibre-Web | 0.6.27 | 8083 | OPDS `/opds` (Basic login) |
| Codex | 1.9.24 | 9810 | OPDS `/opds/v1.2/`, `/opds/v2.0/` |

Ubooquity 3.1 was tried and skipped. Its 3.x config file
(`preferences-2.json`) has a new format, and libraries and users have to be
set up in its admin web UI. Hand-written `opusPaths` entries crash the
scanner with a NullPointerException.

## Folder layout

```
$TEST_SERVERS_DIR/
  content/Manga/Pepper&Carrot/Pepper&Carrot Ep.01.cbz … Ep.06.cbz
  content/Books/<Title>/<Title>.epub          one folder per book (Kavita ignores files in the library root)
  content/Books/Pepper&Carrot PDF/Pepper&Carrot Ep.01.pdf
  content/LICENSES.md
  komga/komga.jar, komga/config/
  kavita/Kavita/ (unpacked release, config/appsettings.json)
  suwayomi/suwayomi.jar, suwayomi/data/, suwayomi/local/Pepper&Carrot -> ../../content/Manga/Pepper&Carrot
  stump/stump_server, stump/client/, stump/config/
  calibre/calibre.app, calibre/library/, calibre/users.sqlite
  calibreweb/app.db
  codex/ (CODEX_CONFIG_DIR)
  tools/cwvenv/ (Calibre-Web), tools/codexvenv/ (Codex), tools/venv/ (Pillow)
  logs/, secrets.txt
```

## Content (legal test material only)

Use only human-made works that are public domain or Creative Commons.
Nothing AI-generated and nothing commercial.

- **Pepper&Carrot** episodes 1–6 by David Revoy, CC BY 4.0,
  <https://www.peppercarrot.com>. The episode list is
  <https://www.peppercarrot.com/0_sources/episodes.json>. Pages are at
  `https://www.peppercarrot.com/0_sources/<episode>/low-res/en_Pepper-and-Carrot_by-David-Revoy_E<NN>P<PP>.jpg`,
  where P00 is the title header. Episode 4's page 5 is a `.gif`; the script
  converts it to JPG. `make_content.py` builds one CBZ per episode, with
  pages `001.jpg…` and a `ComicInfo.xml` (Series, Number, Writer/Penciller,
  LanguageISO=en, Manga=No, Notes with the licence). It also builds
  `Pepper&Carrot Ep.01.pdf` from episode 1. Put `episodes.json` in
  `$TEST_SERVERS_DIR/dl/` first.
- **Project Gutenberg** EPUB3 with images: #11 Alice's Adventures in
  Wonderland, #1342 Pride and Prejudice, #84 Frankenstein. These are public
  domain in the US. Get them from `https://www.gutenberg.org/ebooks/<id>.epub3.images`.
  When gutenberg.org is down (it returned 503 for maintenance on
  2026-11-28), use the official mirror instead:
  `https://gutenberg.pglaf.org/cache/epub/<id>/pg<id>-images-3.epub`.
  Download one file at a time.

Write `content/LICENSES.md` listing every file, its source URL, author,
licence and download date.

## Installing and setting up each server

Java 21 (`/usr/bin/java`) runs Komga and Suwayomi. Python 3.11 venvs run
Calibre-Web and Codex.

### Komga (25600)

- Download: `https://github.com/gotson/komga/releases/download/1.30.2/komga-1.30.2.jar` → `komga/komga.jar`.
- Claim the server:
  `curl -X POST :25600/api/v1/claim -H 'X-Komga-Email: tester@example.com' -H 'X-Komga-Password: mangatest1'`
- Add libraries:
  `POST /api/v1/libraries {"name":"Manga","root":"$T/content/Manga"}`, and the same for Books.
- API key: `POST /api/v2/users/me/api-keys {"comment":"…"}` returns `key`.
  `/api/v1/users/me/api-keys` returns 404.
- Scan: `POST /api/v1/libraries/<id>/scan?deep=true`. After moving files,
  also run `POST /api/v1/libraries/<id>/empty-trash`, or the old series stay.
- Text EPUBs return `pages: []` from `/api/v1/books/<id>/pages`, although
  `media.pagesCount` is 83. PDFs return image pages.

### Kavita (5005)

- Download: `https://github.com/Kareadita/Kavita/releases/download/v0.9.1.4/kavita-osx-arm64.tar.gz`
  → unpack to `kavita/`. Then run `chmod +x kavita/Kavita/Kavita`.
- Create `kavita/Kavita/config/appsettings.json` (the release ships only
  `appsettings-init.json`):
  `{"TokenKey":"<96 random hex chars>","Port":5005,"IpAddresses":"","BaseUrl":"/","Cache":75}`
- Register the admin: `POST /api/Account/register {"username":"tester","password":"mangatest1","email":"tester@example.com"}`.
  The response has `token` (JWT), `apiKey` and `authKeys`. In 0.9.1.4,
  `authKeys` holds one key named `opds` (for the OPDS URL) and one named
  `image-only`.
- Create libraries: `POST /api/Library/create` with a Bearer token. Quirks:
  - `fileGroupTypes` and `excludePatterns` are required:
    `{"name":"Manga","type":0,"folders":["$T/content/Manga"],"fileGroupTypes":[1,2,3,4],"excludePatterns":[],"metadataProvider":3}`.
    Books use `type` 2.
  - `metadataProvider` 1 is rejected as invalid, and 2 gives a 500 error.
    3 works.
  - With `enableMetadata` false (the default for a minimal create),
    Gutenberg EPUBs fail with "Unable to parse any meaningful information".
    Read the library from `GET /api/Library/libraries`, set
    `enableMetadata: true` (and `fileGroupTypes` = `libraryFileTypes`), then
    `POST /api/Library/update`.
  - Files directly in a library root are ignored. Every book needs its own
    folder.
- Scan: `POST /api/Library/scan?libraryId=<id>&force=true`. This is
  asynchronous; check `GET /api/Library/libraries` → `lastScanned`.

### Suwayomi-Server (4567)

- Download: `https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.4.2373/Suwayomi-Server-v2.4.2373.jar`
  → `suwayomi/suwayomi.jar`. `start.sh` passes the settings as
  `-Dsuwayomi.tachidesk.config.server.*` system properties: rootDir, ip,
  port, localSourcePath, no browser, no tray, no web UI.
- Local source: `suwayomi/local/<series folder>/<chapter>.cbz`. A symlink to
  `content/Manga/Pepper&Carrot` works. Install no extensions and no online
  sources.
- Add to the library:
  `mutation { fetchSourceManga(input:{source:"0",type:POPULAR,page:1}) { mangas { id title } } }`
  (it's a mutation, not a query), then
  `mutation { updateMangas(input:{ids:[1], patch:{inLibrary:true}}) { mangas { id } } }`.
- Chapter `pageCount` is -1 until `fetchChapterPages` has run for that
  chapter.

### Stump (10801)

- Download: `https://github.com/stumpapp/stump/releases/download/v0.1.14/macos-arm-build-results.zip`
  → unzip into `stump/`, then `chmod +x stump/stump_server`. The env vars
  are set in `start.sh`: `STUMP_PORT`, `STUMP_CONFIG_DIR`, `STUMP_CLIENT_DIR`.
- Owner account: `POST /api/v2/auth/register {"username":"tester","password":"mangatest1"}`.
  The first user becomes the server owner. `/api/v1/*` only serves the web
  app's HTML.
- Log in: `POST /api/v2/auth/login` (keep the cookie). GraphQL at
  `/api/graphql` needs the cookie; Basic auth isn't accepted there.
- Libraries:
  `mutation { createLibrary(input:{name:"Manga", path:"…/content/Manga", scanAfterPersist:true}) { id } }`.
  Rescan with `scanLibrary(id:)`; remove missing files with `cleanLibrary(id:)`.
- PDFs fail to import ("PDFium is not configured or available") unless
  PDFium is installed. EPUBs import, and OPDS-PSE streams them as 83
  rendered pages.

### calibre content server (8080)

- Download: `https://github.com/kovidgoyal/calibre/releases/download/v9.19.0/calibre-9.19.0.dmg` (about 400 MB).
  Mount it with `hdiutil attach -nobrowse -readonly`, then
  `ditto /Volumes/calibre-9.19.0/calibre.app calibre/calibre.app` (not into
  /Applications), then detach.
- Library: `calibre.app/Contents/MacOS/calibredb add --library-path=calibre/library <file> --series "Pepper&Carrot" --series-index N --authors "David Revoy" --tags …`.
  EPUBs pick up their metadata on their own.
- User:
  `calibre-debug -c "from calibre.srv.users import UserManager; UserManager('…/calibre/users.sqlite').add_user('tester','mangatest1', readonly=False)"`.
- Run: `calibre-server --port=8080 --listen-on=0.0.0.0 --enable-auth --userdb=… --disable-use-bonjour calibre/library`.
  The default auth mode is Digest over http.
- Quirk: in Digest mode, a request that sends **Basic** credentials gets
  `400 Bad Request` with the body "Unsupported authentication method", not a
  401 challenge. Only a request with no credentials gets the
  `401 WWW-Authenticate: Digest realm="calibre", …, algorithm="MD5", qop="auth"`.
- `/opds/new` returns 404. The newest-books feed is
  `/opds/navcatalog/4f6e6577657374?library_id=library`.

### Calibre-Web (8083)

- Install: `python3 -m venv tools/cwvenv && tools/cwvenv/bin/pip install calibreweb`.
  Run `cps -p calibreweb/app.db -g calibreweb/gdrive.db` (see `start.sh`).
- First run redirects to `/admin/dbconfig`. Log in as `admin` / `admin123`,
  then POST `config_calibre_dir` (with the CSRF token) to `/admin/dbconfig`.
  See `calibreweb_setup.py`.
- Quirks:
  - The default password policy (upper case, number and special character
    required) rejects `mangatest1`.
  - The user-edit form saved only partly (it reported `'kindle_mail'`).
  What worked was stopping the server, then setting
  `settings.config_password_policy=0`, `user.name='tester'` and a werkzeug
  `generate_password_hash('mangatest1')` directly in `app.db`.
- OPDS is on by default at `/opds` (Basic login); `/opds/new` lists the
  newest books.

### Codex (9810)

- Install: `python3 -m venv tools/codexvenv && tools/codexvenv/bin/pip install codex`.
  Run with `CODEX_CONFIG_DIR=$T/codex`. The first run writes
  `codex/hypercorn.toml`, which binds 0.0.0.0:9810.
- Users and libraries: `codex_setup.py` uses Django with
  `DJANGO_SETTINGS_MODULE=codex.settings` to create user `tester` and
  libraries for `content/Manga` and `content/Books`. It also sets the
  default `admin` user's password. Restart Codex afterwards so it imports
  the new libraries.
- Codex imports CBZ and PDF; it doesn't treat EPUBs as comics.

## Live tests

From `Packages/MangaCore`:

```
KOMGA_LIVE_URL=http://localhost:25600 KOMGA_LIVE_API_KEY=… swift test --filter KomgaLiveTests
KAVITA_LIVE_URL=http://localhost:5005 KAVITA_LIVE_API_KEY=… swift test --filter KavitaLiveTests
SUWAYOMI_LIVE_URL=http://localhost:4567 swift test --filter SuwayomiLiveTests
CALIBRE_LIVE_URL=http://localhost:8080 CALIBRE_LIVE_USER=tester CALIBRE_LIVE_PASSWORD=mangatest1 swift test --filter CalibreLiveTests
OPDS_LIVE_URL=<catalog> OPDS_LIVE_USER=… OPDS_LIVE_PASSWORD=… swift test --filter OPDSLiveTests
```

`KAVITA_LIVE_API_KEY` is the register response's `apiKey`. The Kavita OPDS
URL uses the `authKeys` entry named `opds`.
