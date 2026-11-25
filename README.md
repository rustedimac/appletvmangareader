# Apple TV Manga Reader

A tvOS manga reader for self-hosted [Kavita](https://www.kavitareader.com) and
[Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) servers. Add as many
servers as you like, read in a two-page spread reader or a seamless vertical
(webtoon) scroll, keep favorites (sortable by title, date favorited, latest
chapter, last read, unread count or server), bookmark pages, and give each
person their own profile.

## Building

Requirements: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open MangaReader.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed. Run
`xcodegen generate` again after pulling changes that add or move files.

To run on a real Apple TV, pick your team under Signing & Capabilities for the
MangaReader target.

## Tests

```sh
# Core logic (clients, storage, spread pairing). Runs on macOS.
cd Packages/MangaCore && swift test

# App UI tests in the tvOS simulator.
xcodebuild test -project MangaReader.xcodeproj -scheme MangaReader \
  -destination 'platform=tvOS Simulator,name=Apple TV' CODE_SIGNING_ALLOWED=NO
```

CI runs both on every push and pull request (`.github/workflows/ci.yml`).

## Free Library

With no setup, the app shows the built-in Free Library: classic comics,
pulp magazines and illustrated books that are public domain in the US, from
the Internet Archive, plus the Pepper&Carrot webcomic by David Revoy (CC BY
4.0). The list is curated in
`Packages/MangaCore/Sources/MangaCore/FreeLibrary/catalog.json`; see
[docs/FREE_LIBRARY.md](docs/FREE_LIBRARY.md) for the rules.

## Game controllers

Xbox, PlayStation and MFi controllers work everywhere the remote does
(d-pad, A to select, B to go back). In the reader, the shoulder buttons
turn pages, the triggers jump chapters, either stick scrolls the vertical
reader, X starts or stops auto-scroll, and Y opens the reader menu.

## Connecting servers

- **Kavita**: the server address and your Kavita username and password.
  Each profile signs in as its own Kavita user, and reading progress,
  read state and Continue Reading sync with that user. The app keeps an
  auth key named "Apple TV Manga Reader" (revocable under Kavita's Manage
  Auth Keys), never the password. Pasting an OPDS URL
  (`http://kavita.local:5000/api/opds/<api-key>`) works too.
- **Suwayomi**: the server address, e.g. `http://suwayomi.local:4567`, plus a
  username and password if the server asks for one (basic auth or UI login).
  Suwayomi keeps one progress per server, so one profile syncs there and the
  others keep progress on the Apple TV, unless the server has user accounts.

See [docs/PROGRESS_SYNC.md](docs/PROGRESS_SYNC.md) for how syncing works.

Bookmarks sync to the server for profiles that sync progress there. Kavita
bookmarks pages and needs the Kavita user to have the Bookmark role; Suwayomi
bookmarks whole chapters, the same flag Mihon shows. Otherwise bookmarks stay
on the Apple TV.

After a successful connection test you pick which Kavita libraries or
Suwayomi categories to import. Each profile has its own choice; change it
later in the server's settings or with "Choose Libraries" on the Library tab.

## iCloud sync and backup

Profiles, servers (without logins), favorites, progress and reader settings
can sync through iCloud once the app is signed with iCloud turned on; until
then Settings → iCloud Sync and Backup offers a Wi‑Fi backup page you open
from a phone or computer. See [docs/ICLOUD.md](docs/ICLOUD.md).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized.
