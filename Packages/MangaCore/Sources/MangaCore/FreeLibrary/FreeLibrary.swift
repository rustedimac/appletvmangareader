import Foundation

/// The built-in Free Library: a curated catalog of public-domain Internet
/// Archive items and the Pepper&Carrot webcomic. It needs no setup, so a
/// fresh install (and App Review) has something to read.
///
/// The catalog lives in `catalog.json` next to this file. The app ships a
/// copy and also fetches the latest one from the repository's main branch,
/// so titles can be added without an app update. See
/// `docs/FREE_LIBRARY.md` for the rules an entry must meet.
public enum FreeLibrary {
    /// Fixed id, so favorites and progress survive the server being
    /// removed and added back.
    public static let serverID = UUID(uuidString: "F7EE11B7-0000-4000-8000-0000000000F1")!

    public static let name = "Free Library"

    public static var config: ServerConfig {
        ServerConfig(id: serverID, kind: .freeLibrary, name: name, baseURL: URL(string: "https://archive.org")!)
    }

    /// Where the newest catalog is published.
    public static let remoteCatalogURL = URL(string:
        "https://raw.githubusercontent.com/rustedimac/appletvmangareader/main/Packages/MangaCore/Sources/MangaCore/FreeLibrary/catalog.json")!

    /// Shown on the Free Library screen in Settings.
    public static let about = """
        Classic comics, pulp magazines and illustrated books that are in the public domain in the US \
        (published in 1930 or earlier), from the Internet Archive, plus the Pepper&Carrot webcomic by \
        David Revoy (CC BY 4.0). Every title is picked by hand; nothing here is searched from the open web.
        """

    /// Reader defaults for Free Library series: everything in it is
    /// Western, read left to right.
    public static func readerSettings(from base: ReaderSettings) -> ReaderSettings {
        var settings = base
        settings.direction = .leftToRight
        return settings
    }
}

public extension AppState {
    /// Adds the Free Library unless the user removed it. Run at launch.
    /// Returns true if the state changed.
    @discardableResult
    mutating func installFreeLibraryIfNeeded() -> Bool {
        guard freeLibraryRemoved != true, server(FreeLibrary.serverID) == nil else { return false }
        addServer(FreeLibrary.config)
        return true
    }

    /// Removes the Free Library and remembers not to add it back.
    mutating func removeFreeLibrary() {
        removeServer(FreeLibrary.serverID)
        freeLibraryRemoved = true
    }

    /// Brings the Free Library back after `removeFreeLibrary()`.
    mutating func restoreFreeLibrary() {
        freeLibraryRemoved = nil
        installFreeLibraryIfNeeded()
    }

    var hasFreeLibrary: Bool { server(FreeLibrary.serverID) != nil }
}

public extension AppState {
    /// Whether the profile saved reader settings for this series itself.
    func hasReaderOverride(for ref: SeriesRef, profile: UUID) -> Bool {
        profileData[profile.uuidString]?.readerOverrides[ref.storageKey] != nil
    }
}

public extension FreeLibrary {
    struct Credit: Hashable, Sendable {
        public var title: String
        public var detail: String
    }

    /// Attribution shown in Settings. Pepper&Carrot's CC BY 4.0 license
    /// requires crediting the author and linking the license.
    static let credits: [Credit] = [
        Credit(title: "Pepper&Carrot by David Revoy",
               detail: "www.peppercarrot.com · Licensed under Creative Commons Attribution 4.0 (CC BY 4.0, creativecommons.org/licenses/by/4.0). Translations by the Pepper&Carrot community. Shown unchanged."),
        Credit(title: "Internet Archive",
               detail: "Scans from archive.org, served through its IIIF image service. Only works published in the US in 1930 or earlier, which are in the public domain in the US. They may still be under copyright in other countries."),
    ]
}
