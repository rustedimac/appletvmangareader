import Foundation

/// What the Favorites tab can be sorted by.
public enum FavoritesSortKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case dateFavorited
    case title
    /// When the newest chapter was added to the server.
    case latestChapter
    /// When this profile last read the series.
    case lastRead
    /// Unread chapter count.
    case unread
    /// Server name, then title.
    case server

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dateFavorited: return "Favorited"
        case .title: return "Title"
        case .latestChapter: return "Updated"
        case .lastRead: return "Last Read"
        case .unread: return "Unread"
        case .server: return "Server"
        }
    }

    /// The direction a key starts in when picked: A to Z for names,
    /// newest or most first for dates and counts.
    public var defaultAscending: Bool {
        switch self {
        case .title, .server: return true
        case .dateFavorited, .latestChapter, .lastRead, .unread: return false
        }
    }

    /// Whether sorting by this key needs data refreshed from the server.
    public var needsServerData: Bool { self == .latestChapter || self == .unread }
}

/// A profile's Favorites sort: a key and a direction.
public struct FavoritesSort: Codable, Hashable, Sendable {
    public var key: FavoritesSortKey
    public var ascending: Bool

    public static let `default` = FavoritesSort(key: .dateFavorited, ascending: false)

    public init(key: FavoritesSortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    private enum CodingKeys: String, CodingKey { case key, ascending }

    /// A key this build doesn't know falls back to date favorited; the
    /// direction is kept either way.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.tolerant(.key, default: FavoritesSort.default.key)
        ascending = c.tolerant(.ascending, default: key.defaultAscending)
    }

    /// Picking the current key flips the direction; picking another key
    /// switches to it in its natural direction.
    public func selecting(_ newKey: FavoritesSortKey) -> FavoritesSort {
        newKey == key ? reversed() : FavoritesSort(key: newKey, ascending: newKey.defaultAscending)
    }

    public func reversed() -> FavoritesSort {
        FavoritesSort(key: key, ascending: !ascending)
    }

    public var directionLabel: String {
        switch key {
        case .title, .server: return ascending ? "A to Z" : "Z to A"
        case .unread: return ascending ? "Fewest First" : "Most First"
        case .dateFavorited, .latestChapter, .lastRead: return ascending ? "Oldest First" : "Newest First"
        }
    }

    /// Sorts favorites. Series missing the value being sorted on (never
    /// read, not refreshed yet) go last in either direction. Ties fall back
    /// to title A to Z.
    public func sorted(_ favorites: [Favorite], lastRead: (SeriesRef) -> Date?,
                       serverName: (UUID) -> String) -> [Favorite] {
        func byTitle(_ a: Favorite, _ b: Favorite) -> Bool {
            let r = a.series.title.localizedStandardCompare(b.series.title)
            if r != .orderedSame { return r == .orderedAscending }
            return a.series.ref.storageKey < b.series.ref.storageKey
        }
        func compare<T: Comparable>(_ x: T?, _ y: T?) -> Bool? {
            switch (x, y) {
            case let (x?, y?): return x == y ? nil : (ascending ? x < y : x > y)
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return nil
            }
        }
        // Compute keys once rather than in the comparator.
        let reads = Dictionary(favorites.map { ($0.series.ref, lastRead($0.series.ref)) }, uniquingKeysWith: { a, _ in a })
        let servers = Dictionary(favorites.map { ($0.series.ref.serverID, serverName($0.series.ref.serverID)) },
                                 uniquingKeysWith: { a, _ in a })
        return favorites.sorted { a, b in
            let decided: Bool?
            switch key {
            case .dateFavorited:
                decided = compare(a.addedAt, b.addedAt)
            case .title:
                let r = a.series.title.localizedStandardCompare(b.series.title)
                decided = r == .orderedSame ? nil : ((r == .orderedAscending) == ascending)
            case .latestChapter:
                decided = compare(a.latestChapterAt, b.latestChapterAt)
            case .lastRead:
                decided = compare(reads[a.series.ref] ?? nil, reads[b.series.ref] ?? nil)
            case .unread:
                decided = compare(a.unreadChapters ?? a.series.unreadCount, b.unreadChapters ?? b.series.unreadCount)
            case .server:
                let x = servers[a.series.ref.serverID] ?? "", y = servers[b.series.ref.serverID] ?? ""
                let r = x.localizedStandardCompare(y)
                decided = r == .orderedSame ? nil : ((r == .orderedAscending) == ascending)
            }
            return decided ?? byTitle(a, b)
        }
    }
}

public extension SeriesDetail {
    /// When the newest chapter arrived: the server's own value when it has
    /// one (Kavita's `lastChapterAdded`), else the newest chapter date.
    var latestChapterDate: Date? {
        latestChapterAt ?? chapters.compactMap(\.updatedAt).max()
    }
}

public extension AppState {
    func favoritesSort(profile: UUID) -> FavoritesSort {
        profileData[profile.uuidString]?.favoritesSort ?? .default
    }

    mutating func setFavoritesSort(_ sort: FavoritesSort, profile: UUID) {
        mutateData(profile) { $0.favoritesSort = sort }
    }

    /// `favorites` in the profile's chosen order.
    func sorted(_ favorites: [Favorite], profile: UUID) -> [Favorite] {
        favoritesSort(profile: profile).sorted(
            favorites,
            lastRead: { progress($0, profile: profile)?.updatedAt },
            serverName: { server($0)?.name ?? "" }
        )
    }

    /// Refreshes a favorite's sort data from series detail. Does nothing if
    /// the series isn't a favorite of this profile.
    mutating func updateFavorite(from detail: SeriesDetail, profile: UUID, now: Date = Date()) {
        let ref = detail.summary.ref
        guard let i = profileData[profile.uuidString]?.favorites.firstIndex(where: { $0.series.ref == ref }) else { return }
        mutateData(profile) { data in
            var f = data.favorites[i]
            f.latestChapterAt = detail.latestChapterDate ?? f.latestChapterAt
            f.unreadChapters = detail.chapters.isEmpty ? f.unreadChapters : detail.chapters.filter { !$0.isRead }.count
            if let unread = detail.summary.unreadCount { f.series.unreadCount = unread }
            f.refreshedAt = now
            data.favorites[i] = f
        }
    }

    /// Notes a refresh attempt without new data (the server didn't answer).
    mutating func markFavoriteRefreshed(_ ref: SeriesRef, profile: UUID, now: Date = Date()) {
        guard let i = profileData[profile.uuidString]?.favorites.firstIndex(where: { $0.series.ref == ref }) else { return }
        mutateData(profile) { $0.favorites[i].refreshedAt = now }
    }

    /// Favorites whose sort data is missing or older than `maxAge`.
    func favoritesNeedingRefresh(profile: UUID, maxAge: TimeInterval, now: Date = Date()) -> [Favorite] {
        (profileData[profile.uuidString]?.favorites ?? []).filter {
            guard let at = $0.refreshedAt else { return true }
            return now.timeIntervalSince(at) > maxAge
        }
    }
}
