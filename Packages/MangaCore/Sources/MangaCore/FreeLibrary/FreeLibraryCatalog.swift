import Foundation

/// The curated list behind the Free Library (`catalog.json`).
public struct FreeLibraryCatalog: Codable, Hashable, Sendable {
    /// Format version. The app ignores remote catalogs with a schema it
    /// doesn't know.
    public static let supportedSchema = 1

    public var schema: Int
    /// Bumped on every edit. A remote catalog replaces the bundled one only
    /// when its version is the same or higher.
    public var version: Int
    public var updated: String
    public var collections: [CollectionEntry]
    public var series: [Series]

    public struct CollectionEntry: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        /// One line for the first-run picker. Optional, so catalogs
        /// without it still decode (and older apps ignore it).
        public var summary: String? = nil
    }

    public enum Source: String, Codable, Hashable, Sendable {
        /// Scanned pages from the Internet Archive via IIIF.
        case internetArchive
        /// Pepper&Carrot episodes, listed live from peppercarrot.com.
        case pepperCarrot
    }

    public enum License: String, Codable, Hashable, Sendable {
        case publicDomainUS
        case ccBy4

        public var displayName: String {
            switch self {
            case .publicDomainUS: return "Public domain in the US"
            case .ccBy4: return "CC BY 4.0"
            }
        }
    }

    public struct Series: Codable, Hashable, Sendable {
        /// Stable id used in favorites and progress. Never change it.
        public var id: String
        public var title: String
        public var creators: [String]
        /// Year or range shown to the user, e.g. "1905–1914".
        public var published: String
        public var collection: String
        public var synopsis: String
        public var genres: [String]?
        public var license: License
        /// Why the work is free to use, e.g. "Published in the US in 1926."
        public var rights: String
        public var source: Source
        /// Internet Archive identifier whose cover image to show. Defaults
        /// to the first chapter's.
        public var cover: String?
        /// Internet Archive items, in reading order. Unused for Pepper&Carrot.
        public var chapters: [ChapterEntry]?
        /// When the entry was added to the catalog (yyyy-MM-dd), for
        /// "Newly Added".
        public var added: String
    }

    public struct ChapterEntry: Codable, Hashable, Sendable {
        /// Internet Archive identifier.
        public var identifier: String
        public var title: String
        /// Page count, if known (the item's `imagecount`).
        public var pages: Int?
    }

    /// Problems that would make an entry unsafe or unusable. Empty means
    /// the catalog is fine. Remote catalogs with problems are ignored.
    public var problems: [String] {
        var found: [String] = []
        if schema != Self.supportedSchema { found.append("unsupported schema \(schema)") }
        let collectionIDs = Set(collections.map(\.id))
        var seen = Set<String>()
        for s in series {
            if !seen.insert(s.id).inserted { found.append("duplicate series id \(s.id)") }
            if !collectionIDs.contains(s.collection) { found.append("\(s.id): unknown collection \(s.collection)") }
            if s.rights.trimmingCharacters(in: .whitespaces).isEmpty { found.append("\(s.id): missing rights") }
            switch s.source {
            case .internetArchive:
                guard s.license == .publicDomainUS else { found.append("\(s.id): IA items must be US public domain"); break }
                let chapters = s.chapters ?? []
                if chapters.isEmpty { found.append("\(s.id): no chapters") }
                for c in chapters where !Self.isValidIdentifier(c.identifier) {
                    found.append("\(s.id): bad identifier \(c.identifier)")
                }
                if let cover = s.cover, !Self.isValidIdentifier(cover) { found.append("\(s.id): bad cover \(cover)") }
            case .pepperCarrot:
                if s.license != .ccBy4 { found.append("\(s.id): Pepper&Carrot is CC BY 4.0") }
            }
        }
        return found
    }

    /// Internet Archive identifiers are letters, digits, `.`, `-` and `_`.
    /// Checked so a catalog entry can only ever point at an archive.org item.
    public static func isValidIdentifier(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 100 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    public static func decode(_ data: Data) throws -> FreeLibraryCatalog {
        do {
            return try JSONDecoder().decode(FreeLibraryCatalog.self, from: data)
        } catch {
            throw MangaError.decoding("Free Library catalog: \(error)")
        }
    }

    /// The copy shipped with the app.
    public static let bundled: FreeLibraryCatalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? decode(data) else {
            assertionFailure("catalog.json missing or invalid")
            return FreeLibraryCatalog(schema: supportedSchema, version: 0, updated: "", collections: [], series: [])
        }
        return catalog
    }()
}
