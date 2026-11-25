import Foundation

/// The kind of backend a server connection talks to.
public enum ServerKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case kavita
    case suwayomi
    case komga
    case opds
    /// The built-in Free Library (public-domain Internet Archive items and
    /// Pepper&Carrot). Always there; never typed in by the user.
    case freeLibrary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kavita: return "Kavita"
        case .suwayomi: return "Suwayomi"
        case .komga: return "Komga"
        case .opds: return "OPDS"
        case .freeLibrary: return "Free Library"
        }
    }

    /// The kinds offered when adding a server, in picker order.
    public static var userAddable: [ServerKind] { [.kavita, .komga, .suwayomi, .opds] }
}

/// A saved server connection, shared by every profile. Credentials are not
/// stored here; each profile has its own `ServerCredential` in a `SecretStore`.
public struct ServerConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ServerKind
    public var name: String
    /// The main address. Every URL the clients build starts with it;
    /// `FailoverTransport` swaps it for whichever address answers.
    public var baseURL: URL
    /// Other addresses of the same server, e.g. a remote or reverse-proxy
    /// address for when the Apple TV isn't on the home network. Tried in
    /// order after `baseURL` (see `ServerAddressRouter`). Saved only when
    /// there are some, so older builds and backups read the same JSON.
    public var alternateURLs: [URL]

    public init(id: UUID = UUID(), kind: ServerKind, name: String, baseURL: URL, alternateURLs: [URL] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.alternateURLs = alternateURLs
    }

    /// Every address in the order they're tried, main address first,
    /// without repeats.
    public var addresses: [URL] {
        var seen = Set<String>()
        return ([baseURL] + alternateURLs).filter { seen.insert($0.absoluteString).inserted }
    }

    /// True when there's more than one address to choose from.
    public var hasAlternateAddresses: Bool { addresses.count > 1 }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, baseURL, alternateURLs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ServerKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(URL.self, forKey: .baseURL)
        alternateURLs = (try? c.decodeIfPresent([URL].self, forKey: .alternateURLs)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(baseURL, forKey: .baseURL)
        if !alternateURLs.isEmpty { try c.encode(alternateURLs, forKey: .alternateURLs) }
    }
}

/// Credentials one profile uses for one server. Kavita uses an API key
/// (each Kavita user has their own); Suwayomi uses optional basic auth.
public struct ServerCredential: Codable, Hashable, Sendable {
    public var apiKey: String?
    public var username: String?
    public var password: String?

    public init(apiKey: String? = nil, username: String? = nil, password: String? = nil) {
        self.apiKey = apiKey
        self.username = username
        self.password = password
    }
}

/// A person using the Apple TV. Favorites, local progress and server
/// credentials are kept separately for each profile.
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol name shown on the profile picker.
    public var symbol: String
    /// Index into the app's avatar color palette.
    public var colorIndex: Int

    public init(id: UUID = UUID(), name: String, symbol: String = "person.fill", colorIndex: Int = 0) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
    }
}

/// How a profile uses a particular server.
public struct ProfileServerSettings: Codable, Hashable, Sendable {
    /// Whether reading progress is written back to the server. Kavita
    /// progress belongs to the signed-in Kavita user, so this is normally on.
    /// Suwayomi has a single progress per server, so only one profile should
    /// sync; the others keep progress locally.
    public var syncProgressToServer: Bool
    /// Which Kavita libraries or Suwayomi categories this profile imports
    /// from the server, by `MangaCategory.id`. Nil means all of them,
    /// including ones added to the server later; that is the default for
    /// servers saved before this setting existed.
    public var selectedCategoryIDs: Set<String>?

    public init(syncProgressToServer: Bool = true, selectedCategoryIDs: Set<String>? = nil) {
        self.syncProgressToServer = syncProgressToServer
        self.selectedCategoryIDs = selectedCategoryIDs
    }

    /// Whether a series in these categories is shown. A series whose
    /// categories aren't known (e.g. a favorite saved by an older version)
    /// is always shown.
    public func includes(categories ids: [String]?) -> Bool {
        guard let selected = selectedCategoryIDs, let ids else { return true }
        return ids.contains(where: selected.contains)
    }

    public func includes(_ series: SeriesSummary) -> Bool {
        includes(categories: series.memberCategoryIDs)
    }
}

/// A grouping of series on a server: a Kavita library or a Suwayomi category.
public struct MangaCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var order: Int

    public init(id: String, name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}

/// Globally unique reference to a series: which server, and the id on it.
public struct SeriesRef: Codable, Hashable, Sendable {
    public var serverID: UUID
    public var seriesID: String

    public init(serverID: UUID, seriesID: String) {
        self.serverID = serverID
        self.seriesID = seriesID
    }
}

public struct SeriesSummary: Codable, Hashable, Identifiable, Sendable {
    public var ref: SeriesRef
    public var title: String
    public var coverURL: URL?
    public var unreadCount: Int?
    /// Kavita needs the library id when saving progress.
    public var libraryID: String?
    /// File format, when the server says. Nil means page images.
    public var format: ContentFormat?
    /// The Suwayomi categories the series is in ("0" is Default). Nil when
    /// unknown. Kavita uses `libraryID` instead.
    public var categoryIDs: [String]?
    /// Total and read pages, when the server reports them (Kavita). Used
    /// for poster progress badges.
    public var pageCount: Int?
    public var pagesRead: Int?
    /// Number of chapters, when known (Suwayomi library grids).
    public var chapterCount: Int?

    public var id: SeriesRef { ref }

    public init(ref: SeriesRef, title: String, coverURL: URL?, unreadCount: Int? = nil, libraryID: String? = nil,
                categoryIDs: [String]? = nil, pageCount: Int? = nil, pagesRead: Int? = nil, chapterCount: Int? = nil,
                format: ContentFormat? = nil) {
        self.ref = ref
        self.title = title
        self.coverURL = coverURL
        self.unreadCount = unreadCount
        self.libraryID = libraryID
        self.categoryIDs = categoryIDs
        self.pageCount = pageCount
        self.pagesRead = pagesRead
        self.chapterCount = chapterCount
        self.format = format
    }

    /// The `MangaCategory` ids this series belongs to, or nil if unknown.
    public var memberCategoryIDs: [String]? {
        categoryIDs ?? libraryID.map { [$0] }
    }
}

public struct Chapter: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var seriesRef: SeriesRef
    /// Kavita volume id, needed for progress updates. Nil for Suwayomi.
    public var volumeID: String?
    public var title: String
    /// Sort key, ascending = reading order.
    public var number: Double
    public var pageCount: Int
    /// Zero-based index of the last page read.
    public var lastPageRead: Int
    public var isRead: Bool
    public var updatedAt: Date?
    /// File format, when the server says. Nil means page images. For EPUB
    /// and text, `pageCount` and `lastPageRead` count sections, not pages.
    public var format: ContentFormat?

    public init(id: String, seriesRef: SeriesRef, volumeID: String? = nil, title: String, number: Double,
                pageCount: Int, lastPageRead: Int = 0, isRead: Bool = false, updatedAt: Date? = nil,
                format: ContentFormat? = nil) {
        self.format = format
        self.id = id
        self.seriesRef = seriesRef
        self.volumeID = volumeID
        self.title = title
        self.number = number
        self.pageCount = pageCount
        self.lastPageRead = lastPageRead
        self.isRead = isRead
        self.updatedAt = updatedAt
    }
}

public struct SeriesDetail: Codable, Hashable, Sendable {
    public var summary: SeriesSummary
    public var synopsis: String?
    public var authors: [String]
    public var genres: [String]
    public var status: String?
    /// Chapters sorted in reading order (first to last).
    public var chapters: [Chapter]
    /// When the server last added a chapter, if it tracks that (Kavita's
    /// `lastChapterAdded`). See `latestChapterDate`.
    public var latestChapterAt: Date? = nil

    public init(summary: SeriesSummary, synopsis: String?, authors: [String], genres: [String],
                status: String?, chapters: [Chapter]) {
        self.summary = summary
        self.synopsis = synopsis
        self.authors = authors
        self.genres = genres
        self.status = status
        self.chapters = chapters
    }

    /// The chapter to open when the user presses "Continue": the first
    /// unread chapter, or the first chapter if all are read.
    public var continueChapter: Chapter? {
        chapters.first(where: { !$0.isRead }) ?? chapters.first
    }
}

/// One page of a chapter. `size` is known up front for Kavita (from
/// file-dimensions) and discovered after download for Suwayomi.
public struct PageDescriptor: Hashable, Sendable {
    public var index: Int
    public var url: URL
    public var size: PageSize?

    public init(index: Int, url: URL, size: PageSize? = nil) {
        self.index = index
        self.url = url
        self.size = size
    }
}

public struct PageSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// A page wider than it is tall is treated as a two-page spread.
    public var isWide: Bool { height > 0 && width / height > 1.0 }
}

/// Rows on a server's home screen.
public enum HomeFeed: String, CaseIterable, Sendable, Identifiable {
    case continueReading
    case recentlyUpdated
    case newlyAdded

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .continueReading: return "Continue Reading"
        case .recentlyUpdated: return "Recently Updated"
        case .newlyAdded: return "Newly Added"
        }
    }
}

public struct Paged<Item: Sendable>: Sendable {
    public var items: [Item]
    public var hasMore: Bool

    public init(items: [Item], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}
