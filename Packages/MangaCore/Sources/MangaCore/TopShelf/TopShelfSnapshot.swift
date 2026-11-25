import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The App Group the app and its Top Shelf extension share.
public enum AppGroup {
    public static let identifier = "group.com.rustedimac.MangaReader"

    /// The shared container, or nil when the app isn't signed with the App
    /// Group (CI simulator builds). Top Shelf content is skipped then.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// What the Top Shelf shows, written by the app and read by the extension.
/// Kept tiny: the extension runs with a small memory limit, so it only
/// decodes this file and points at cover files the app already wrote.
public struct TopShelfSnapshot: Codable, Hashable, Sendable {
    public enum SectionKind: String, Codable, Sendable {
        case continueReading
        case favorites
    }

    public struct Item: Codable, Hashable, Sendable {
        /// Stable across snapshots (`SeriesRef.storageKey`).
        public var id: String
        public var serverID: UUID
        public var title: String
        /// File name of the cover inside the covers folder, if there is one.
        public var coverFile: String?
        /// Where the cover comes from, so the app can download it.
        public var coverURL: URL?
        /// Opens the series page.
        public var displayURL: URL
        /// Opens the reader.
        public var playURL: URL
    }

    public struct Section: Codable, Hashable, Sendable {
        public var kind: SectionKind
        public var title: String
        public var items: [Item]
    }

    public var profileID: UUID?
    public var sections: [Section]

    public init(profileID: UUID?, sections: [Section]) {
        self.profileID = profileID
        self.sections = sections
    }

    public static let empty = TopShelfSnapshot(profileID: nil, sections: [])

    /// Every cover the snapshot refers to.
    public var covers: [(file: String, url: URL, serverID: UUID)] {
        var seen = Set<String>()
        var out: [(String, URL, UUID)] = []
        for item in sections.flatMap(\.items) {
            guard let file = item.coverFile, let url = item.coverURL, seen.insert(file).inserted else { continue }
            out.append((file, url, item.serverID))
        }
        return out
    }

    /// Builds the Top Shelf for the active profile: Continue Reading, then
    /// Favorites with new chapters first. Series already in Continue Reading
    /// aren't repeated under Favorites. Empty sections are left out.
    public static func make(from state: AppState, continueLimit: Int = 10, favoritesLimit: Int = 12) -> TopShelfSnapshot {
        guard let profile = state.activeProfile?.id else { return .empty }
        let serverIDs = Set(state.servers.map(\.id))

        let continuing = state.continueReading(profile: profile, limit: continueLimit)
        let continueItems = continuing.map { entry in
            item(entry.series, title: entry.series.title,
                 play: .read(entry.series.ref, chapterID: entry.progress.chapterID, page: entry.progress.page,
                             profile: profile),
                 profile: profile)
        }

        let shown = Set(continuing.map(\.series.ref))
        let favoriteItems = state.favoritesForTopShelf(profile: profile, limit: favoritesLimit + shown.count)
            .filter { serverIDs.contains($0.series.ref.serverID) && !shown.contains($0.series.ref) }
            .prefix(favoritesLimit)
            .map { fav -> Item in
                let s = fav.series
                let unread = fav.newChapterCount
                let title = unread > 0 ? "\(s.title) · \(unread) new" : s.title
                // Play resumes where the profile left off, or opens the series.
                let play: DeepLink
                if let p = state.progress(s.ref, profile: profile), !p.chapterID.isEmpty {
                    play = .read(s.ref, chapterID: p.chapterID, page: p.page, profile: profile)
                } else {
                    play = .series(s.ref, profile: profile)
                }
                return item(s, title: title, play: play, profile: profile)
            }

        var sections: [Section] = []
        if !continueItems.isEmpty {
            sections.append(Section(kind: .continueReading, title: "Continue Reading", items: continueItems))
        }
        if !favoriteItems.isEmpty {
            sections.append(Section(kind: .favorites, title: "Favorites", items: Array(favoriteItems)))
        }
        return TopShelfSnapshot(profileID: profile, sections: sections)
    }

    private static func item(_ s: SeriesSummary, title: String, play: DeepLink, profile: UUID) -> Item {
        Item(id: s.ref.storageKey, serverID: s.ref.serverID, title: title,
             coverFile: s.coverURL.map(coverFileName(for:)), coverURL: s.coverURL,
             displayURL: DeepLink.series(s.ref, profile: profile).url, playURL: play.url)
    }

    /// A file name for a cover that doesn't contain the URL (Kavita cover
    /// URLs carry an API key). Query parameters named `apiKey` are dropped
    /// first so a changed key doesn't re-download every cover.
    public static func coverFileName(for url: URL) -> String {
        var key = url.absoluteString
        if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.queryItems = c.queryItems?.filter { $0.name.lowercased() != "apikey" }
            if c.queryItems?.isEmpty == true { c.queryItems = nil }
            key = c.url?.absoluteString ?? key
        }
        return hexDigest(key) + ".jpg"
    }

    static func hexDigest(_ s: String) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        // FNV-1a fallback for platforms without CryptoKit.
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", h)
        #endif
    }
}

/// Reads and writes the snapshot and covers in a directory (the App Group
/// container's `TopShelf` folder in the app).
public struct TopShelfStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `<App Group>/TopShelf`, or nil without the App Group.
    public static var shared: TopShelfStore? {
        AppGroup.containerURL.map { TopShelfStore(directory: $0.appendingPathComponent("TopShelf", isDirectory: true)) }
    }

    public var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    public var coversDirectory: URL { directory.appendingPathComponent("Covers", isDirectory: true) }

    public func coverURL(_ file: String) -> URL { coversDirectory.appendingPathComponent(file) }

    public func hasCover(_ file: String) -> Bool {
        FileManager.default.fileExists(atPath: coverURL(file).path)
    }

    public func load() -> TopShelfSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    /// Writes the snapshot. Returns false when nothing changed, so the
    /// caller can skip telling the system to reload the Top Shelf.
    @discardableResult
    public func save(_ snapshot: TopShelfSnapshot) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        if let old = try? Data(contentsOf: snapshotURL), old == data { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: snapshotURL, options: .atomic)
        return true
    }

    public func saveCover(_ data: Data, file: String) throws {
        try FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        try data.write(to: coverURL(file), options: .atomic)
    }

    /// Deletes covers no longer in `keep`.
    public func pruneCovers(keeping keep: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: coversDirectory.path)) ?? []
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: coverURL(file))
        }
    }
}
