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
    /// Enough to draw the series on a local Continue Reading row (no
    /// secrets, see `SeriesSummary.withoutSecrets`).
    public var series: SeriesSummary?
    /// Changes not yet confirmed by the server, oldest first.
    public var pending: [PendingProgress]
    /// Chapters this profile marked unread. They show as unread even when
    /// the server (another profile's progress) says they're read.
    public var unreadChapterIDs: Set<String>
    /// Set when this profile marked the whole series unread: from then on
    /// only local progress counts and the server's read state is ignored.
    public var ignoresServerProgress: Bool

    public init(chapterID: String, page: Int, updatedAt: Date = Date(), readChapterIDs: Set<String> = [],
                unreadChapterIDs: Set<String> = [], ignoresServerProgress: Bool = false,
                series: SeriesSummary? = nil, pending: [PendingProgress] = []) {
        self.chapterID = chapterID
        self.page = page
        self.updatedAt = updatedAt
        self.readChapterIDs = readChapterIDs
        self.unreadChapterIDs = unreadChapterIDs
        self.ignoresServerProgress = ignoresServerProgress
        self.series = series
        self.pending = pending
    }

    private enum CodingKeys: String, CodingKey {
        case chapterID, page, updatedAt, readChapterIDs, unreadChapterIDs, ignoresServerProgress, series, pending
    }

    // Older saved state has no unread, series or pending fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterID = try c.decode(String.self, forKey: .chapterID)
        page = try c.decode(Int.self, forKey: .page)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        readChapterIDs = try c.decodeIfPresent(Set<String>.self, forKey: .readChapterIDs) ?? []
        unreadChapterIDs = try c.decodeIfPresent(Set<String>.self, forKey: .unreadChapterIDs) ?? []
        ignoresServerProgress = try c.decodeIfPresent(Bool.self, forKey: .ignoresServerProgress) ?? false
        series = try c.decodeIfPresent(SeriesSummary.self, forKey: .series)
        pending = try c.decodeIfPresent([PendingProgress].self, forKey: .pending) ?? []
    }

    // Skip empty optional fields to keep AppState small.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chapterID, forKey: .chapterID)
        try c.encode(page, forKey: .page)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(readChapterIDs, forKey: .readChapterIDs)
        if !unreadChapterIDs.isEmpty { try c.encode(unreadChapterIDs, forKey: .unreadChapterIDs) }
        if ignoresServerProgress { try c.encode(true, forKey: .ignoresServerProgress) }
        try c.encodeIfPresent(series, forKey: .series)
        if !pending.isEmpty { try c.encode(pending, forKey: .pending) }
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
    /// Genres, tags and age limit hidden for this profile. Nil (the
    /// default, and for data saved before filters existed) hides nothing.
    public var contentFilter: ContentFilter?
    /// Whether opening the profile asks for its PIN. The PIN itself is in
    /// the Keychain (`PINStore`); without one this does nothing.
    public var requiresPINToOpen: Bool?
    /// Book (EPUB/text) reader settings. Nil until changed.
    public var bookSettings: BookSettings?
    /// Bookmarked pages across every server.
    public var bookmarks: [Bookmark]
    /// How the Favorites tab is sorted.
    public var favoritesSort: FavoritesSort
    /// Home layout, library sorts and reading styles, poster size. Nil
    /// until changed (see `AppState+Browse.swift`).
    public var browse: BrowsePreferences?
    /// Webtoon auto-scroll speed (1...10); nil uses the default. Use
    /// `autoScrollLevel`.
    public var webtoonAutoScrollLevel: Int? = nil
    /// Title and cover of series this profile has read, keyed by
    /// `SeriesRef.storageKey`, so Continue Reading on the Top Shelf can draw
    /// them without the server. Optional so older saved state decodes.
    public var recentSeries: [String: SeriesSummary]?

    public init(serverSettings: [String: ProfileServerSettings] = [:],
                favorites: [Favorite] = [],
                progress: [String: SeriesProgress] = [:],
                defaultReaderSettings: ReaderSettings = .default,
                readerOverrides: [String: ReaderSettings] = [:],
                bookSettings: BookSettings? = nil,
                bookmarks: [Bookmark] = [],
                favoritesSort: FavoritesSort = .default,
                recentSeries: [String: SeriesSummary]? = nil,
                browse: BrowsePreferences? = nil,
                contentFilter: ContentFilter? = nil,
                requiresPINToOpen: Bool? = nil) {
        self.bookSettings = bookSettings
        self.serverSettings = serverSettings
        self.favorites = favorites
        self.progress = progress
        self.defaultReaderSettings = defaultReaderSettings
        self.readerOverrides = readerOverrides
        self.bookmarks = bookmarks
        self.favoritesSort = favoritesSort
        self.recentSeries = recentSeries
        self.browse = browse
        self.contentFilter = contentFilter
        self.requiresPINToOpen = requiresPINToOpen
    }

    private enum CodingKeys: String, CodingKey {
        case serverSettings, favorites, progress, defaultReaderSettings, readerOverrides, bookSettings, bookmarks, favoritesSort, webtoonAutoScrollLevel, recentSeries, browse,
             contentFilter, requiresPINToOpen
    }

    // State saved by older versions lacks the newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverSettings = try c.decodeIfPresent([String: ProfileServerSettings].self, forKey: .serverSettings) ?? [:]
        favorites = try c.decodeIfPresent([Favorite].self, forKey: .favorites) ?? []
        progress = try c.decodeIfPresent([String: SeriesProgress].self, forKey: .progress) ?? [:]
        defaultReaderSettings = try c.decodeIfPresent(ReaderSettings.self, forKey: .defaultReaderSettings) ?? .default
        readerOverrides = try c.decodeIfPresent([String: ReaderSettings].self, forKey: .readerOverrides) ?? [:]
        // A bad value falls back to the defaults instead of failing the profile.
        bookSettings = try? c.decodeIfPresent(BookSettings.self, forKey: .bookSettings)
        bookmarks = try c.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        favoritesSort = (try? c.decodeIfPresent(FavoritesSort.self, forKey: .favoritesSort)) ?? .default
        webtoonAutoScrollLevel = try c.decodeIfPresent(Int.self, forKey: .webtoonAutoScrollLevel)
        // A damaged list only loses Top Shelf titles, never the profile.
        recentSeries = try? c.decodeIfPresent([String: SeriesSummary].self, forKey: .recentSeries)
        // A browse shape this build can't read falls back to defaults.
        browse = (try? c.decodeIfPresent(BrowsePreferences.self, forKey: .browse)) ?? nil
        contentFilter = try c.decodeIfPresent(ContentFilter.self, forKey: .contentFilter)
        requiresPINToOpen = try c.decodeIfPresent(Bool.self, forKey: .requiresPINToOpen)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(serverSettings, forKey: .serverSettings)
        try c.encode(favorites, forKey: .favorites)
        try c.encode(progress, forKey: .progress)
        try c.encode(defaultReaderSettings, forKey: .defaultReaderSettings)
        try c.encode(readerOverrides, forKey: .readerOverrides)
        try c.encodeIfPresent(bookSettings, forKey: .bookSettings)
        if !bookmarks.isEmpty { try c.encode(bookmarks, forKey: .bookmarks) }
        if favoritesSort != .default { try c.encode(favoritesSort, forKey: .favoritesSort) }
        try c.encodeIfPresent(webtoonAutoScrollLevel, forKey: .webtoonAutoScrollLevel)
        try c.encodeIfPresent(recentSeries, forKey: .recentSeries)
        try c.encodeIfPresent(browse, forKey: .browse)
        try c.encodeIfPresent(contentFilter, forKey: .contentFilter)
        try c.encodeIfPresent(requiresPINToOpen, forKey: .requiresPINToOpen)
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
    /// The profile to open without asking "Who's reading?". Only used when
    /// the app runs as the current Apple TV user, where this state belongs
    /// to that user alone (see `ProfileLaunch`).
    public var rememberedProfileID: UUID?
    /// True once the user removed the built-in Free Library, so it isn't
    /// added back on the next launch. Nil in state saved before it existed.
    public var freeLibraryRemoved: Bool?

    public init(version: Int = AppState.currentVersion, profiles: [Profile] = [], activeProfileID: UUID? = nil,
                servers: [ServerConfig] = [], profileData: [String: ProfileData] = [:],
                rememberedProfileID: UUID? = nil) {
        self.version = version
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.servers = servers
        self.profileData = profileData
        self.rememberedProfileID = rememberedProfileID
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
        for server in servers where server.kind == .suwayomi || server.kind == .freeLibrary {
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
        if rememberedProfileID == id { rememberedProfileID = nil }
        return true
    }

    public mutating func setActiveProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    // MARK: Servers

    public mutating func addServer(_ server: ServerConfig) {
        // The built-in Free Library stays after the user's own servers.
        if server.kind != .freeLibrary, let i = servers.firstIndex(where: { $0.kind == .freeLibrary }) {
            servers.insert(server, at: i)
        } else {
            servers.append(server)
        }
        // Default sync rule: Kavita always syncs (progress is per Kavita user);
        // Suwayomi syncs only for the active profile that added it. The Free
        // Library has no server progress, so it never syncs.
        for profile in profiles {
            let syncs = server.kind != .freeLibrary && (server.kind == .kavita || profile.id == activeProfile?.id)
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
            data.recentSeries = data.recentSeries?.filter { !$0.key.hasPrefix(prefix) }
            data.browse?.removeServer(id)
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

    /// Records where the profile is. `series` (when given) is kept, minus
    /// secrets, for the local Continue Reading row.
    public mutating func recordProgress(_ ref: SeriesRef, chapterID: String, page: Int, completed: Bool,
                                        profile: UUID, now: Date = Date(), series: SeriesSummary? = nil) {
        mutateData(profile) { data in
            var p = data.progress[ref.storageKey] ?? SeriesProgress(chapterID: chapterID, page: page, updatedAt: now)
            p.chapterID = chapterID
            p.page = page
            p.updatedAt = now
            if let series { p.series = series.withoutSecrets }
            if completed { p.readChapterIDs.insert(chapterID) }
            // Reading a chapter again means its progress is real, not a reset.
            p.unreadChapterIDs.remove(chapterID)
            data.progress[ref.storageKey] = p
        }
    }

    /// Marks chapters of one series unread for this profile: drops them
    /// from the read set and resets the page if one was the open chapter.
    public mutating func markUnread(_ ref: SeriesRef, chapterIDs: Set<String>, profile: UUID, now: Date = Date()) {
        guard !chapterIDs.isEmpty else { return }
        mutateData(profile) { data in
            var p = data.progress[ref.storageKey] ?? SeriesProgress(chapterID: "", page: 0, updatedAt: now)
            p.readChapterIDs.subtract(chapterIDs)
            if !p.ignoresServerProgress { p.unreadChapterIDs.formUnion(chapterIDs) }
            if chapterIDs.contains(p.chapterID) { p.page = 0 }
            p.updatedAt = now
            data.progress[ref.storageKey] = p
        }
    }

    /// Marks chapters of one series read for this profile. The open
    /// chapter and page (where Continue resumes) stay as they are.
    public mutating func markRead(_ ref: SeriesRef, chapterIDs: Set<String>, profile: UUID, now: Date = Date()) {
        guard !chapterIDs.isEmpty else { return }
        mutateData(profile) { data in
            var p = data.progress[ref.storageKey] ?? SeriesProgress(chapterID: "", page: 0, updatedAt: now)
            p.readChapterIDs.formUnion(chapterIDs)
            p.unreadChapterIDs.subtract(chapterIDs)
            p.updatedAt = now
            data.progress[ref.storageKey] = p
        }
    }

    /// Marks a whole series unread for this profile. Server read state is
    /// ignored from now on, so profiles that don't sync see it unread too.
    public mutating func markSeriesUnread(_ ref: SeriesRef, profile: UUID, now: Date = Date()) {
        mutateData(profile) { data in
            data.progress[ref.storageKey] = SeriesProgress(chapterID: "", page: 0, updatedAt: now,
                                                           ignoresServerProgress: true)
        }
    }

    /// Applies local progress on top of what the server reported, for
    /// profiles that don't sync to this server.
    public func applyingLocalProgress(to detail: SeriesDetail, profile: UUID) -> SeriesDetail {
        guard let p = progress(detail.summary.ref, profile: profile) else { return detail }
        var d = detail
        for i in d.chapters.indices {
            let id = d.chapters[i].id
            if p.ignoresServerProgress || p.unreadChapterIDs.contains(id) {
                d.chapters[i].isRead = false
                d.chapters[i].lastPageRead = 0
            }
            if p.readChapterIDs.contains(id) { d.chapters[i].isRead = true }
            if id == p.chapterID { d.chapters[i].lastPageRead = p.page }
        }
        return d
    }

    // MARK: Reader settings

    public func readerSettings(for ref: SeriesRef, profile: UUID) -> ReaderSettings {
        let data = profileData[profile.uuidString]
        return (data?.readerOverrides[ref.storageKey] ?? data?.defaultReaderSettings ?? .default).normalizedPairing
    }

    public mutating func setReaderSettings(_ settings: ReaderSettings, for ref: SeriesRef, profile: UUID) {
        mutateData(profile) { $0.readerOverrides[ref.storageKey] = settings.normalizedPairing }
    }

    public mutating func setDefaultReaderSettings(_ settings: ReaderSettings, profile: UUID) {
        mutateData(profile) { $0.defaultReaderSettings = settings.normalizedPairing }
    }

    // MARK: Content filter and PIN

    public func contentFilter(profile: UUID) -> ContentFilter {
        profileData[profile.uuidString]?.contentFilter ?? .none
    }

    public mutating func setContentFilter(_ filter: ContentFilter, profile: UUID) {
        mutateData(profile) { $0.contentFilter = filter.isActive ? filter : nil }
    }

    public func requiresPINToOpen(profile: UUID) -> Bool {
        profileData[profile.uuidString]?.requiresPINToOpen ?? false
    }

    public mutating func setRequiresPINToOpen(_ on: Bool, profile: UUID) {
        mutateData(profile) { $0.requiresPINToOpen = on ? true : nil }
    }

    /// Favorites the profile may see: in its imported libraries/categories
    /// and not hidden by its content filter. `hidden` maps server ids to
    /// the ids its filter hides (see `ContentVisibility`); with an active
    /// filter, servers missing from it show none of their favorites.
    public func visibleFavorites(profile: UUID, hidden: [UUID: Set<String>]) -> [Favorite] {
        let filter = contentFilter(profile: profile)
        let favorites = visibleFavorites(profile: profile)
        let allowed = Set(ContentVisibility.visible(favorites.map(\.series), filter: filter, hidden: hidden).map(\.ref))
        return favorites.filter { allowed.contains($0.series.ref) }
    }

    // MARK: Book settings

    public func bookSettings(profile: UUID) -> BookSettings {
        profileData[profile.uuidString]?.bookSettings ?? .default
    }

    public mutating func setBookSettings(_ settings: BookSettings, profile: UUID) {
        mutateData(profile) { $0.bookSettings = settings }
    }

    // MARK: Helpers

    mutating func mutateData(_ profile: UUID, _ body: (inout ProfileData) -> Void) {
        var data = profileData[profile.uuidString] ?? ProfileData()
        body(&data)
        profileData[profile.uuidString] = data
    }
}
