import Foundation

/// A favorited series, kept per profile. Stores enough to draw a poster
/// without asking the server.
public struct Favorite: Codable, Hashable, Identifiable, Sendable {
    public var series: SeriesSummary
    public var addedAt: Date

    public var id: SeriesRef { series.ref }

    public init(series: SeriesSummary, addedAt: Date = Date()) {
        self.series = series
        self.addedAt = addedAt
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
    /// Chapters this profile marked unread. They show as unread even when
    /// the server (another profile's progress) says they're read.
    public var unreadChapterIDs: Set<String>
    /// Set when this profile marked the whole series unread: from then on
    /// only local progress counts and the server's read state is ignored.
    public var ignoresServerProgress: Bool

    public init(chapterID: String, page: Int, updatedAt: Date = Date(), readChapterIDs: Set<String> = [],
                unreadChapterIDs: Set<String> = [], ignoresServerProgress: Bool = false) {
        self.chapterID = chapterID
        self.page = page
        self.updatedAt = updatedAt
        self.readChapterIDs = readChapterIDs
        self.unreadChapterIDs = unreadChapterIDs
        self.ignoresServerProgress = ignoresServerProgress
    }

    private enum CodingKeys: String, CodingKey {
        case chapterID, page, updatedAt, readChapterIDs, unreadChapterIDs, ignoresServerProgress
    }

    // Older saved state has no unread fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterID = try c.decode(String.self, forKey: .chapterID)
        page = try c.decode(Int.self, forKey: .page)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        readChapterIDs = try c.decodeIfPresent(Set<String>.self, forKey: .readChapterIDs) ?? []
        unreadChapterIDs = try c.decodeIfPresent(Set<String>.self, forKey: .unreadChapterIDs) ?? []
        ignoresServerProgress = try c.decodeIfPresent(Bool.self, forKey: .ignoresServerProgress) ?? false
    }

    // Skip the unread fields when empty to keep AppState small.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chapterID, forKey: .chapterID)
        try c.encode(page, forKey: .page)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(readChapterIDs, forKey: .readChapterIDs)
        if !unreadChapterIDs.isEmpty { try c.encode(unreadChapterIDs, forKey: .unreadChapterIDs) }
        if ignoresServerProgress { try c.encode(true, forKey: .ignoresServerProgress) }
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
    /// Webtoon auto-scroll speed (1...10); nil uses the default. Use
    /// `autoScrollLevel`.
    public var webtoonAutoScrollLevel: Int? = nil

    public init(serverSettings: [String: ProfileServerSettings] = [:],
                favorites: [Favorite] = [],
                progress: [String: SeriesProgress] = [:],
                defaultReaderSettings: ReaderSettings = .default,
                readerOverrides: [String: ReaderSettings] = [:]) {
        self.serverSettings = serverSettings
        self.favorites = favorites
        self.progress = progress
        self.defaultReaderSettings = defaultReaderSettings
        self.readerOverrides = readerOverrides
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
