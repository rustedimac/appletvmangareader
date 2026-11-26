import Foundation

/// Lists a server keeps beside its libraries: reading lists (an ordered
/// run of chapters, possibly from several series), collections (a hand-
/// picked set of series) and smart filters (a saved series search). Kavita
/// has all three; other servers offer none for now (Komga has collections
/// and read lists too, a possible follow-up).
///
/// Read-only: the app browses them and reads from them, but never creates,
/// edits or reorders them.
public enum ServerCollectionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case readingList
    case collection
    case smartFilter

    /// Plural title for the screen and the Library button.
    public var title: String {
        switch self {
        case .readingList: return "Reading Lists"
        case .collection: return "Collections"
        case .smartFilter: return "Smart Filters"
        }
    }

    /// "Reading List", for one of them.
    public var singularTitle: String {
        switch self {
        case .readingList: return "Reading List"
        case .collection: return "Collection"
        case .smartFilter: return "Smart Filter"
        }
    }

    public var symbolName: String {
        switch self {
        case .readingList: return "list.number"
        case .collection: return "square.stack"
        case .smartFilter: return "line.3.horizontal.decrease.circle"
        }
    }

    /// What a list of this kind holds: series, or chapters in order.
    public var holdsChapters: Bool { self == .readingList }

    /// Shown when the server has none.
    public var emptyMessage: String {
        switch self {
        case .readingList: return "Reading lists you make or that are promoted on the server show up here."
        case .collection: return "Collections you make or that are promoted on the server show up here."
        case .smartFilter: return "Filters you save in the server's web app show up here."
        }
    }
}

/// Which `ServerCollectionKind`s a server can list.
public struct ServerCollectionSupport: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let readingLists = ServerCollectionSupport(rawValue: 1 << 0)
    public static let collections = ServerCollectionSupport(rawValue: 1 << 1)
    public static let smartFilters = ServerCollectionSupport(rawValue: 1 << 2)
    public static let all: ServerCollectionSupport = [.readingLists, .collections, .smartFilters]

    public func contains(_ kind: ServerCollectionKind) -> Bool {
        switch kind {
        case .readingList: return contains(.readingLists)
        case .collection: return contains(.collections)
        case .smartFilter: return contains(.smartFilters)
        }
    }

    /// The kinds in display order.
    public var kinds: [ServerCollectionKind] { ServerCollectionKind.allCases.filter(contains) }
}

/// One reading list, collection or smart filter on a server.
public struct ServerCollection: Codable, Hashable, Identifiable, Sendable {
    public var serverID: UUID
    public var kind: ServerCollectionKind
    /// The server's id for it.
    public var collectionID: String
    public var title: String
    public var summary: String?
    /// Chapters (reading list) or series (collection). Nil when unknown,
    /// and always for smart filters, which the server works out on demand.
    public var itemCount: Int?
    /// Shown to every user of the server (Kavita "promoted").
    public var promoted: Bool
    public var coverURL: URL?
    /// Server-specific data needed to load it (a smart filter's encoded
    /// filter).
    public var payload: String?

    public var id: String { "\(serverID.uuidString)|\(kind.rawValue)|\(collectionID)" }

    public init(serverID: UUID, kind: ServerCollectionKind, collectionID: String, title: String,
                summary: String? = nil, itemCount: Int? = nil, promoted: Bool = false,
                coverURL: URL? = nil, payload: String? = nil) {
        self.serverID = serverID
        self.kind = kind
        self.collectionID = collectionID
        self.title = title
        self.summary = summary
        self.itemCount = itemCount
        self.promoted = promoted
        self.coverURL = coverURL
        self.payload = payload
    }

    /// "12 chapters · Promoted", for the line under the title.
    public var caption: String? {
        var parts: [String] = []
        if let itemCount {
            let noun = kind.holdsChapters ? (itemCount == 1 ? "item" : "items") : "series"
            parts.append("\(itemCount) \(noun)")
        }
        if promoted { parts.append("Promoted") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Server lists in the order the app shows them: by title, natural
    /// order, ignoring case; ties by id so the order is stable.
    public static func sorted(_ items: [ServerCollection]) -> [ServerCollection] {
        items.sorted { a, b in
            let order = NaturalSort.compare(a.title, b.title)
            return order != .orderedSame ? order == .orderedAscending : a.collectionID < b.collectionID
        }
    }
}

/// One chapter in a reading list, in list order.
public struct ReadingListEntry: Codable, Hashable, Identifiable, Sendable {
    /// The server's id for the list item.
    public var itemID: String
    public var order: Int
    public var seriesRef: SeriesRef
    public var seriesTitle: String
    public var chapterID: String
    public var volumeID: String?
    public var libraryID: String?
    /// The chapter's name in the list ("Volume 2", "Chapter 5: …").
    public var title: String
    public var pageCount: Int
    public var pagesRead: Int
    public var format: ContentFormat?
    public var coverURL: URL?

    public var id: String { itemID }

    public init(itemID: String, order: Int, seriesRef: SeriesRef, seriesTitle: String, chapterID: String,
                volumeID: String? = nil, libraryID: String? = nil, title: String, pageCount: Int, pagesRead: Int,
                format: ContentFormat? = nil, coverURL: URL? = nil) {
        self.itemID = itemID
        self.order = order
        self.seriesRef = seriesRef
        self.seriesTitle = seriesTitle
        self.chapterID = chapterID
        self.volumeID = volumeID
        self.libraryID = libraryID
        self.title = title
        self.pageCount = pageCount
        self.pagesRead = pagesRead
        self.format = format
        self.coverURL = coverURL
    }

    public var isRead: Bool { pageCount > 0 && pagesRead >= pageCount }

    /// 0...1 for a started chapter, nil when unread or finished.
    public var progress: Double? {
        guard pageCount > 0, pagesRead > 0, pagesRead < pageCount else { return nil }
        return Double(pagesRead) / Double(pageCount)
    }

    /// The series the entry belongs to, enough to open series detail.
    public var seriesSummary: SeriesSummary {
        SeriesSummary(ref: seriesRef, title: seriesTitle, coverURL: nil, libraryID: libraryID, format: format)
    }

    /// The entry to continue a list from: the first one not finished, or
    /// the first entry when every one is read (start over). Nil when empty.
    public static func resumeEntry(in entries: [ReadingListEntry]) -> ReadingListEntry? {
        entries.first { !$0.isRead } ?? entries.first
    }

    /// "Continue", "Start" or "Read Again", for the list's main button.
    public static func resumeLabel(in entries: [ReadingListEntry]) -> String {
        if entries.allSatisfy(\.isRead) { return "Read Again" }
        return entries.contains { $0.pagesRead > 0 } ? "Continue" : "Start"
    }
}
