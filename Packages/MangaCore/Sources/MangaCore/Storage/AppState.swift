import Foundation

/// A favorited series, kept per profile. Stores enough to draw a poster
/// without asking the server.
public struct Favorite: Codable, Hashable, Identifiable, Sendable {
    public var series: SeriesSummary
    public var addedAt: Date
    /// When the series' newest chapter was added, for sorting. Refreshed
    /// from series detail (see `AppState.updateFavorite(from:)`).
    public var latestChapterAt: Date?
    /// Unread chapters as of the last refresh, for sorting.
    public var unreadChapters: Int?
    /// When `latestChapterAt` and `unreadChapters` were last refreshed.
    public var refreshedAt: Date?

    public var id: SeriesRef { series.ref }

    public init(series: SeriesSummary, addedAt: Date = Date(), latestChapterAt: Date? = nil,
                unreadChapters: Int? = nil, refreshedAt: Date? = nil) {
        self.series = series
        self.addedAt = addedAt
        self.latestChapterAt = latestChapterAt
        self.unreadChapters = unreadChapters
        self.refreshedAt = refreshedAt
    }
}

/// Local reading progress for one series. Always written, so a profile that
/// doesn't sync to the server (e.g. a second profile on a Suwayomi server)
/// still resumes where it left off.
public struct SeriesProgress: Codable, Hashable, Sendable {
    public var chapterID: String
    /// Zero-based page within `chapterID`.
    public var page: Int
    public var updatedAt: Date
    public var readChapterIDs: Set<String>

    public init(chapterID: String, page: Int, updatedAt: Date = Date(), readChapterIDs: Set<String> = []) {
        self.chapterID = chapterID
        self.page = page
        self.updatedAt = updatedAt
        self.readChapterIDs = readChapterIDs
    }
}

/// Everything that belongs to one profile.
public struct ProfileData: Codable, Hashable, Sendable {
    /// Keyed by server id (uuidString).
    public var serverSettings: [String: ProfileServerSettings]
    public var favorites: [Favorite]
    /// Keyed by `SeriesRef.storageKey`.
    public var progress: [String: SeriesProgress]
    public var defaultReaderSettings: ReaderSettings
    /// Per-series reader overrides, keyed by `SeriesRef.storageKey`.
    public var readerOverrides: [String: ReaderSettings]
    /// Bookmarked pages across every server.
    public var bookmarks: [Bookmark]
    /// How the Favorites tab is sorted.
    public var favoritesSort: FavoritesSort
    /// Webtoon auto-scroll speed (1...10); nil uses the default. Use
    /// `autoScrollLevel`.
    public var webtoonAutoScrollLevel: Int? = nil

    public init(serverSettings: [String: ProfileServerSettings] = [:],
                favorites: [Favorite] = [],
                progress: [String: SeriesProgress] = [:],
                defaultReaderSettings: ReaderSettings = .default,
                readerOverrides: [String: ReaderSettings] = [:],
                bookmarks: [Bookmark] = [],
                favoritesSort: FavoritesSort = .default) {
        self.serverSettings = serverSettings
        self.favorites = favorites
        self.progress = progress
        self.defaultReaderSettings = defaultReaderSettings
        self.readerOverrides = readerOverrides
        self.bookmarks = bookmarks
        self.favoritesSort = favoritesSort
    }

    private enum CodingKeys: String, CodingKey {
        case serverSettings, favorites, progress, defaultReaderSettings, readerOverrides, bookmarks, favoritesSort, webtoonAutoScrollLevel
    }

    // State saved by older versions lacks the newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverSettings = try c.decodeIfPresent([String: ProfileServerSettings].self, forKey: .serverSettings) ?? [:]
        favorites = try c.decodeIfPresent([Favorite].self, forKey: .favorites) ?? []
        progress = try c.decodeIfPresent([String: SeriesProgress].self, forKey: .progress) ?? [:]
        defaultReaderSettings = try c.decodeIfPresent(ReaderSettings.self, forKey: .defaultReaderSettings) ?? .default
        readerOverrides = try c.decodeIfPresent([String: ReaderSettings].self, forKey: .readerOverrides) ?? [:]
        bookmarks = try c.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        favoritesSort = (try? c.decodeIfPresent(FavoritesSort.self, forKey: .favoritesSort)) ?? .default
        webtoonAutoScrollLevel = try c.decodeIfPresent(Int.self, forKey: .webtoonAutoScrollLevel)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(serverSettings, forKey: .serverSettings)
        try c.encode(favorites, forKey: .favorites)
        try c.encode(progress, forKey: .progress)
        try c.encode(defaultReaderSettings, forKey: .defaultReaderSettings)
        try c.encode(readerOverrides, forKey: .readerOverrides)
        if !bookmarks.isEmpty { try c.encode(bookmarks, forKey: .bookmarks) }
        if favoritesSort != .default { try c.encode(favoritesSort, forKey: .favoritesSort) }
        try c.encodeIfPresent(webtoonAutoScrollLevel, forKey: .webtoonAutoScrollLevel)
    }
}

public extension SeriesRef {
    var storageKey: String { "\(serverID.uuidString)|\(seriesID)" }
}

/// The app's persisted, non-secret state. Value type with pure mutations so
/// it's easy to test; `StateStore` loads and saves it.
public struct AppState: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var profiles: [Profile]
    public var activeProfileID: UUID?
    public var servers: [ServerConfig]
    /// Keyed by profile id (uuidString).
    public var profileData: [String: ProfileData]

    public init(version: Int = AppState.currentVersion, profiles: [Profile] = [], activeProfileID: UUID? = nil,
                servers: [ServerConfig] = [], profileData: [String: ProfileData] = [:]) {
        self.version = version
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.servers = servers
        self.profileData = profileData
    }

    /// A fresh install has one profile so the app works without setup.
    public static func initial() -> AppState {
        let profile = Profile(name: "Me")
        return AppState(profiles: [profile], activeProfileID: profile.id,
                        profileData: [profile.id.uuidString: ProfileData()])
    }

    public var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    // MARK: Profiles

    @discardableResult
    public mutating func addProfile(name: String, symbol: String = "person.fill", colorIndex: Int? = nil) -> Profile {
        let profile = Profile(name: name, symbol: symbol, colorIndex: colorIndex ?? profiles.count)
        profiles.append(profile)
        var data = ProfileData()
        // Suwayomi keeps a single progress per server, owned by the first
        // profile. New profiles read locally there unless they opt in.
        for server in servers where server.kind == .suwayomi {
            data.serverSettings[server.id.uuidString] = ProfileServerSettings(syncProgressToServer: false)
        }
        profileData[profile.id.uuidString] = data
        if activeProfileID == nil { activeProfileID = profile.id }
        return profile
    }

    public mutating func updateProfile(_ profile: Profile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[i] = profile
    }

    /// Removes a profile and its data. The last profile can't be removed.
    /// Returns false if nothing was removed.
    @discardableResult
    public mutating func removeProfile(_ id: UUID) -> Bool {
        guard profiles.count > 1, let i = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: i)
        profileData[id.uuidString] = nil
        if activeProfileID == id { activeProfileID = profiles.first?.id }
        return true
    }

    public mutating func setActiveProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    // MARK: Servers

    public mutating func addServer(_ server: ServerConfig) {
        servers.append(server)
        // Default sync rule: Kavita always syncs (progress is per Kavita user);
        // Suwayomi syncs only for the active profile that added it.
        for profile in profiles {
            let syncs = server.kind == .kavita || profile.id == activeProfile?.id
            mutateData(profile.id) { $0.serverSettings[server.id.uuidString] = ProfileServerSettings(syncProgressToServer: syncs) }
        }
    }

    public mutating func updateServer(_ server: ServerConfig) {
        guard let i = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[i] = server
    }

    /// Removes a server and everything that refers to it in every profile.
    /// The caller also deletes its credentials from the `SecretStore`.
    public mutating func removeServer(_ id: UUID) {
        servers.removeAll { $0.id == id }
        let prefix = id.uuidString + "|"
        for key in Array(profileData.keys) {
            guard var data = profileData[key] else { continue }
            data.serverSettings[id.uuidString] = nil
            data.favorites.removeAll { $0.series.ref.serverID == id }
            data.bookmarks.removeAll { $0.series.ref.serverID == id }
            data.progress = data.progress.filter { !$0.key.hasPrefix(prefix) }
            data.readerOverrides = data.readerOverrides.filter { !$0.key.hasPrefix(prefix) }
            profileData[key] = data
        }
    }

    public func server(_ id: UUID) -> ServerConfig? { servers.first { $0.id == id } }

    public func serverSettings(profile: UUID, server: UUID) -> ProfileServerSettings {
        profileData[profile.uuidString]?.serverSettings[server.uuidString] ?? ProfileServerSettings()
    }

    public mutating func setServerSettings(_ settings: ProfileServerSettings, profile: UUID, server: UUID) {
        mutateData(profile) { $0.serverSettings[server.uuidString] = settings }
    }

    /// The libraries/categories a profile imports from a server (nil = all).
    public func selectedCategories(profile: UUID, server: UUID) -> Set<String>? {
        serverSettings(profile: profile, server: server).selectedCategoryIDs
    }

    public mutating func setSelectedCategories(_ ids: Set<String>?, profile: UUID, server: UUID) {
        var settings = serverSettings(profile: profile, server: server)
        settings.selectedCategoryIDs = ids
        setServerSettings(settings, profile: profile, server: server)
    }

    // MARK: Favorites

    public func favorites(profile: UUID) -> [Favorite] {
        (profileData[profile.uuidString]?.favorites ?? []).sorted { $0.addedAt > $1.addedAt }
    }

    /// Favorites from libraries/categories the profile imports, newest first.
    public func visibleFavorites(profile: UUID) -> [Favorite] {
        favorites(profile: profile).filter {
            serverSettings(profile: profile, server: $0.series.ref.serverID).includes($0.series)
        }
    }

    public func isFavorite(_ ref: SeriesRef, profile: UUID) -> Bool {
        profileData[profile.uuidString]?.favorites.contains { $0.series.ref == ref } ?? false
    }

    public mutating func setFavorite(_ series: SeriesSummary, _ favorite: Bool, profile: UUID, now: Date = Date()) {
        mutateData(profile) { data in
            data.favorites.removeAll { $0.series.ref == series.ref }
            if favorite { data.favorites.append(Favorite(series: series, addedAt: now)) }
        }
    }

    // MARK: Progress

    public func progress(_ ref: SeriesRef, profile: UUID) -> SeriesProgress? {
        profileData[profile.uuidString]?.progress[ref.storageKey]
    }

    public mutating func recordProgress(_ ref: SeriesRef, chapterID: String, page: Int, completed: Bool,
                                        profile: UUID, now: Date = Date()) {
        mutateData(profile) { data in
            var p = data.progress[ref.storageKey] ?? SeriesProgress(chapterID: chapterID, page: page, updatedAt: now)
            p.chapterID = chapterID
            p.page = page
            p.updatedAt = now
            if completed { p.readChapterIDs.insert(chapterID) }
            data.progress[ref.storageKey] = p
        }
    }

    /// Applies local progress on top of what the server reported, for
    /// profiles that don't sync to this server.
    public func applyingLocalProgress(to detail: SeriesDetail, profile: UUID) -> SeriesDetail {
        guard let p = progress(detail.summary.ref, profile: profile) else { return detail }
        var d = detail
        for i in d.chapters.indices {
            if p.readChapterIDs.contains(d.chapters[i].id) { d.chapters[i].isRead = true }
            if d.chapters[i].id == p.chapterID { d.chapters[i].lastPageRead = p.page }
        }
        return d
    }

    // MARK: Reader settings

    public func readerSettings(for ref: SeriesRef, profile: UUID) -> ReaderSettings {
        let data = profileData[profile.uuidString]
        return data?.readerOverrides[ref.storageKey] ?? data?.defaultReaderSettings ?? .default
    }

    public mutating func setReaderSettings(_ settings: ReaderSettings, for ref: SeriesRef, profile: UUID) {
        mutateData(profile) { $0.readerOverrides[ref.storageKey] = settings }
    }

    public mutating func setDefaultReaderSettings(_ settings: ReaderSettings, profile: UUID) {
        mutateData(profile) { $0.defaultReaderSettings = settings }
    }

    // MARK: Helpers

    mutating func mutateData(_ profile: UUID, _ body: (inout ProfileData) -> Void) {
        var data = profileData[profile.uuidString] ?? ProfileData()
        body(&data)
        profileData[profile.uuidString] = data
    }
}
