# Apple TV Manga Reader

A tvOS manga reader for self-hosted [Kavita](https://www.kavitareader.com) and
[Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) servers. Add as many
servers as you like, read in a two-page spread reader or a seamless vertical
(webtoon) scroll, keep favorites, and give each person their own profile.

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

## Connecting servers

- **Kavita**: paste your OPDS URL (User Settings → 3rd Party Clients), e.g.
  `http://kavita.local:5000/api/opds/<api-key>`. The app extracts the server
  address and API key from it. Each profile can use its own Kavita user.
- **Suwayomi**: the server address, e.g. `http://suwayomi.local:4567`, plus a
  username and password if basic auth is enabled.

After a successful connection test you pick which Kavita libraries or
Suwayomi categories to import. Each profile has its own choice; change it
later in the server's settings or with "Choose Libraries" on the Library tab.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized.
