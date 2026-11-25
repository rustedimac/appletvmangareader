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
    public var baseURL: URL

    public init(id: UUID = UUID(), kind: ServerKind, name: String, baseURL: URL) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
    }
}

/// Credentials one profile uses for one server.
///
/// Kavita: `apiKey` is an auth key of the profile's Kavita user (made at
/// sign-in, or pasted from an OPDS URL); `username` is who it belongs to,
/// for display. The Kavita password is never stored.
///
/// Suwayomi: optional `username` and `password`. `suwayomiLogin` records
/// whether the server takes them through its `login` mutation (UI_LOGIN,
/// Bearer tokens) or as HTTP basic auth.
public struct ServerCredential: Codable, Hashable, Sendable {
    public var apiKey: String?
    public var username: String?
    public var password: String?
    public var suwayomiLogin: SuwayomiLoginMode?

    public init(apiKey: String? = nil, username: String? = nil, password: String? = nil,
                suwayomiLogin: SuwayomiLoginMode? = nil) {
        self.apiKey = apiKey
        self.username = username
        self.password = password
        self.suwayomiLogin = suwayomiLogin
    }
}

/// How a Suwayomi server takes a username and password.
public enum SuwayomiLoginMode: String, Codable, Hashable, Sendable {
    /// HTTP basic auth (`BASIC_AUTH` mode).
    case basic
    /// `login` mutation and Bearer tokens (`UI_LOGIN` mode).
    case token
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
    /// The Suwayomi categories the series is in ("0" is Default). Nil when
    /// unknown. Kavita uses `libraryID` instead.
    public var categoryIDs: [String]?

    public var id: SeriesRef { ref }

    public init(ref: SeriesRef, title: String, coverURL: URL?, unreadCount: Int? = nil, libraryID: String? = nil,
                categoryIDs: [String]? = nil) {
        self.ref = ref
        self.title = title
        self.coverURL = coverURL
        self.unreadCount = unreadCount
        self.libraryID = libraryID
        self.categoryIDs = categoryIDs
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
    /// When the server last saw progress on this chapter, for this user.
    /// Nil when it was never read. Used to resolve sync conflicts.
    public var lastReadAt: Date?

    public init(id: String, seriesRef: SeriesRef, volumeID: String? = nil, title: String, number: Double,
                pageCount: Int, lastPageRead: Int = 0, isRead: Bool = false, updatedAt: Date? = nil,
                lastReadAt: Date? = nil) {
        self.id = id
        self.seriesRef = seriesRef
        self.volumeID = volumeID
        self.title = title
        self.number = number
        self.pageCount = pageCount
        self.lastPageRead = lastPageRead
        self.isRead = isRead
        self.updatedAt = updatedAt
        self.lastReadAt = lastReadAt
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

    /// The chapter to open when the user presses "Continue", following
    /// Kavita's continue-point rule:
    /// 1. the unfinished chapter with progress that was read most recently;
    /// 2. else the first unread chapter after the last read one;
    /// 3. else the first unread chapter, or the first chapter if all are read.
    public var continueChapter: Chapter? {
        var latest: Chapter?
        for chapter in chapters where !chapter.isRead && chapter.lastPageRead > 0 {
            // Ties (or no dates) go to the later chapter in reading order.
            if latest == nil || (chapter.lastReadAt ?? .distantPast) >= (latest?.lastReadAt ?? .distantPast) {
                latest = chapter
            }
        }
        if let latest { return latest }
        if let lastRead = chapters.lastIndex(where: \.isRead),
           let next = chapters[(lastRead + 1)...].first(where: { !$0.isRead }) {
            return next
        }
        return chapters.first(where: { !$0.isRead }) ?? chapters.first
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
