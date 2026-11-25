import Foundation
import Observation
import MangaCore

/// The app-wide model. Owns persisted state, secrets and server clients.
/// Every screen reads it from the SwiftUI environment:
/// `@Environment(AppModel.self) private var model`.
@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    @ObservationIgnored let stateStore: StateStore
    @ObservationIgnored let secrets: SecretStore
    /// Profile PIN hashes (Keychain in the app, in memory for UI tests).
    @ObservationIgnored let pins: PINStore
    /// Which PIN-protected profiles are unlocked this session.
    private(set) var locks = ProfileLocks()
    /// Bumped whenever a PIN is set or removed. The Keychain isn't
    /// observable, so views that read `hasPIN` depend on this instead.
    private(set) var pinRevision = 0
    /// For each server, the series the active profile's content filter
    /// hides there. Used for lists built from local data (Favorites, Top
    /// Shelf). A server missing here hides all of its favorites while a
    /// filter is on. Refreshed by `refreshHiddenSeries()`.
    private(set) var hiddenSeries: [UUID: Set<String>] = [:]
    @ObservationIgnored let transport: HTTPTransport
    @ObservationIgnored private var clientCache: [String: MangaServer] = [:]
    /// True while the "Who's reading?" picker is showing. Set at launch when
    /// there's more than one profile, and by "Switch Profile" in Settings.
    var isPickingProfile = false
    /// Builds server clients, limited to a set of library/category ids (nil
    /// for all). UI tests swap in `SampleLibraryServer` (see
    /// `AppModel+Demo.swift`).
    @ObservationIgnored var makeClient: (ServerConfig, ServerCredential?, Set<String>?, HTTPTransport) -> MangaServer = {
        MangaServerFactory.make(config: $0, credential: $1, categoryScope: $2, transport: $3)
    }

    init(stateStore: StateStore, secrets: SecretStore, pins: PINStore = InMemoryPINStore(),
         transport: HTTPTransport = URLSessionTransport()) {
        self.stateStore = stateStore
        self.secrets = secrets
        self.pins = pins
        self.transport = transport
        self.state = stateStore.load()
        self.isPickingProfile = state.profiles.count > 1
        if needsPINToOpen(activeProfile.id) { isPickingProfile = true }
    }

    static func live() -> AppModel {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let store = StateStore(backing: InMemoryKeyValueStore())
            let pins = InMemoryPINStore()
            if let seeded = UITestingSeed.state() { store.save(seeded) }
            UITestingSeed.seedPINs(store.load(), into: pins)
            let model = AppModel(stateStore: store, secrets: InMemorySecretStore(), pins: pins)
            if ProcessInfo.processInfo.arguments.contains("-demoServers") { model.installDemoServers() }
            if ProcessInfo.processInfo.arguments.contains("-liveServers") { model.installLiveServersFromEnvironment() }
            return model
        }
        return AppModel(stateStore: StateStore(backing: UserDefaultsStore()), secrets: KeychainSecretStore(),
                        pins: KeychainPINStore())
    }

    // MARK: State

    /// The only way to change persisted state. Saves after every change.
    func update(_ change: (inout AppState) -> Void) {
        change(&state)
        stateStore.save(state)
    }

    var activeProfile: Profile { state.activeProfile ?? Profile(name: "Me") }
    var servers: [ServerConfig] { state.servers }

    func switchProfile(_ id: UUID) {
        let previous = activeProfile.id
        update { $0.setActiveProfile(id) }
        clientCache.removeAll()
        hiddenSeries = [:]
        if previous != id { locks.lock(previous) }
    }

    @discardableResult
    func addProfile(name: String, symbol: String, colorIndex: Int) -> Profile {
        var added: Profile?
        update { added = $0.addProfile(name: name, symbol: symbol, colorIndex: colorIndex) }
        return added!
    }

    func updateProfile(_ profile: Profile) {
        update { $0.updateProfile(profile) }
    }

    /// Removes a profile, its data and its server logins. The last profile
    /// can't be removed.
    func removeProfile(_ id: UUID) {
        guard state.profiles.count > 1 else { return }
        for server in state.servers { secrets.setCredential(nil, profile: id, server: server.id) }
        pins.setPIN(nil, profile: id)
        pinRevision += 1
        locks.lock(id)
        update { $0.removeProfile(id) }
        clientCache.removeAll()
    }

    // MARK: Servers

    /// A client for a server, signed in as the active profile and limited to
    /// the libraries/categories that profile imports.
    func client(for server: ServerConfig) -> MangaServer {
        let scope = selectedCategories(for: server)
        let filter = contentFilter
        let key = "\(activeProfile.id.uuidString)|\(server.id.uuidString)|\(server.baseURL.absoluteString)|\(Self.scopeKey(scope))|\(filter.cacheKey)"
        if let cached = clientCache[key] { return cached }
        let credential = secrets.credential(profile: activeProfile.id, server: server.id)
        // Every screen gets the profile's content filter through the client.
        let client = ContentFilteredServer.wrapping(makeClient(server, credential, scope, transport), filter: filter)
        clientCache[key] = client
        return client
    }

    /// A stable string for a selection, for cache keys and `.task(id:)`.
    static func scopeKey(_ scope: Set<String>?) -> String {
        scope.map { "only:" + $0.sorted().joined(separator: ",") } ?? "all"
    }

    /// Changes whenever the active profile's selection for `server` or its
    /// content filter does.
    func scopeKey(for server: ServerConfig) -> String {
        Self.scopeKey(selectedCategories(for: server)) + "|" + contentFilter.cacheKey
    }

    func client(for ref: SeriesRef) -> MangaServer? {
        state.server(ref.serverID).map(client(for:))
    }

    func credential(for server: ServerConfig) -> ServerCredential? {
        secrets.credential(profile: activeProfile.id, server: server.id)
    }

    func saveServer(_ server: ServerConfig, credential: ServerCredential?) {
        if state.server(server.id) == nil {
            update { $0.addServer(server) }
        } else {
            update { $0.updateServer(server) }
        }
        secrets.setCredential(credential, profile: activeProfile.id, server: server.id)
        clientCache.removeAll()
    }

    /// Checks a server and login without saving them.
    func testConnection(_ server: ServerConfig, credential: ServerCredential?) async throws -> String {
        try await makeClient(server, credential, nil, transport).validate()
    }

    /// Every library/category on a server, selected or not, for the picker.
    /// Works before the server is saved.
    func availableCategories(_ server: ServerConfig, credential: ServerCredential?) async throws -> [MangaCategory] {
        try await makeClient(server, credential, nil, transport).categories()
    }

    /// The library/category ids the active profile imports (nil = all).
    func selectedCategories(for server: ServerConfig) -> Set<String>? {
        state.selectedCategories(profile: activeProfile.id, server: server.id)
    }

    func setSelectedCategories(_ ids: Set<String>?, for server: ServerConfig) {
        let profile = activeProfile.id
        update { $0.setSelectedCategories(ids, profile: profile, server: server.id) }
    }

    func serverSettings(for server: ServerConfig) -> ProfileServerSettings {
        state.serverSettings(profile: activeProfile.id, server: server.id)
    }

    func setServerSettings(_ settings: ProfileServerSettings, for server: ServerConfig) {
        let profile = activeProfile.id
        update { $0.setServerSettings(settings, profile: profile, server: server.id) }
    }

    func removeServer(_ server: ServerConfig) {
        secrets.removeCredentials(server: server.id, profiles: state.profiles.map(\.id))
        update { $0.removeServer(server.id) }
        clientCache.removeAll()
    }

    // MARK: Favorites

    func isFavorite(_ ref: SeriesRef) -> Bool {
        state.isFavorite(ref, profile: activeProfile.id)
    }

    func toggleFavorite(_ series: SeriesSummary) {
        let profile = activeProfile.id
        update { $0.setFavorite(series, !$0.isFavorite(series.ref, profile: profile), profile: profile) }
    }

    // MARK: Progress

    func syncsProgress(to serverID: UUID) -> Bool {
        state.serverSettings(profile: activeProfile.id, server: serverID).syncProgressToServer
    }

    /// Records progress locally, and on the server if this profile syncs there.
    func recordProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async {
        let profile = activeProfile.id
        unreadCountOverrides[chapter.seriesRef] = nil
        update { $0.recordProgress(chapter.seriesRef, chapterID: chapter.id, page: page, completed: completed, profile: profile) }
        guard syncsProgress(to: chapter.seriesRef.serverID), let client = client(for: chapter.seriesRef) else { return }
        try? await client.saveProgress(chapter: chapter, libraryID: libraryID, page: page, completed: completed)
    }

    /// Poster badge counts changed by "Mark as Unread" since the feeds
    /// loaded, so posters update without reloading every row.
    private(set) var unreadCountOverrides: [SeriesRef: Int] = [:]

    func unreadCount(for series: SeriesSummary) -> Int? {
        unreadCountOverrides[series.ref] ?? series.unreadCount
    }

    /// Marks chapters of one series unread for this profile, and on the
    /// server when this profile syncs there.
    func markUnread(_ chapters: [Chapter], in ref: SeriesRef) async throws {
        guard !chapters.isEmpty else { return }
        let profile = activeProfile.id
        update { $0.markUnread(ref, chapterIDs: Set(chapters.map(\.id)), profile: profile) }
        if syncsProgress(to: ref.serverID), let client = client(for: ref) {
            try await client.markUnread(chapters: chapters)
        }
        await refreshUnreadCount(ref)
    }

    /// Marks every chapter of a series unread for this profile, and on the
    /// server when this profile syncs there.
    func markSeriesUnread(_ ref: SeriesRef) async throws {
        let profile = activeProfile.id
        update { $0.markSeriesUnread(ref, profile: profile) }
        if syncsProgress(to: ref.serverID), let client = client(for: ref) {
            try await client.markSeriesUnread(ref.seriesID)
        }
        await refreshUnreadCount(ref)
    }

    private func refreshUnreadCount(_ ref: SeriesRef) async {
        guard let detail = try? await seriesDetail(ref) else { return }
        // A profile that doesn't sync can't trust the server's count.
        unreadCountOverrides[ref] = syncsProgress(to: ref.serverID)
            ? detail.posterUnreadCount
            : detail.chapters.filter { !$0.isRead }.count
    }

    /// Series detail with this profile's local progress applied when it
    /// doesn't sync to the server.
    func seriesDetail(_ ref: SeriesRef) async throws -> SeriesDetail {
        guard let client = client(for: ref) else { throw MangaError.notFound }
        let detail = try await client.seriesDetail(ref.seriesID)
        if syncsProgress(to: ref.serverID) { return detail }
        return state.applyingLocalProgress(to: detail, profile: activeProfile.id)
    }

    // MARK: Reader settings

    func readerSettings(for ref: SeriesRef) -> ReaderSettings {
        state.readerSettings(for: ref, profile: activeProfile.id)
    }

    func setReaderSettings(_ settings: ReaderSettings, for ref: SeriesRef) {
        let profile = activeProfile.id
        update { $0.setReaderSettings(settings, for: ref, profile: profile) }
    }

    /// The active profile's reader settings for series without an override.
    var defaultReaderSettings: ReaderSettings {
        state.profileData[activeProfile.id.uuidString]?.defaultReaderSettings ?? .default
    }

    func setDefaultReaderSettings(_ settings: ReaderSettings) {
        let profile = activeProfile.id
        update { $0.setDefaultReaderSettings(settings, profile: profile) }
    }

    // MARK: Content filter

    /// What the active profile hides (genres, tags, age limit).
    var contentFilter: ContentFilter { state.contentFilter(profile: activeProfile.id) }

    func setContentFilter(_ filter: ContentFilter) {
        let profile = activeProfile.id
        update { $0.setContentFilter(filter, profile: profile) }
        clientCache.removeAll()
        hiddenSeries = [:]
    }

    /// Genres and tags across every server, for the filter checklist.
    /// Servers that can't be reached are skipped.
    func contentFacets() async -> ContentFacets {
        let clients = servers.map { client(for: $0) }
        let all = await withTaskGroup(of: ContentFacets?.self) { group in
            for c in clients { group.addTask { try? await c.contentFacets() } }
            var out: [ContentFacets] = []
            for await f in group { if let f { out.append(f) } }
            return out
        }
        return ContentFacets.merged(all, keeping: contentFilter)
    }

    /// Loads which series each server hides for the active profile, for
    /// `favorites` and Top Shelf. Servers that fail stay missing, so their
    /// favorites stay hidden.
    func refreshHiddenSeries() async {
        let filter = contentFilter
        guard filter.isActive else {
            hiddenSeries = [:]
            return
        }
        let clients = servers.map { client(for: $0) }
        let loaded = await withTaskGroup(of: (UUID, Set<String>?).self) { group in
            for c in clients {
                group.addTask { (c.config.id, try? await c.hiddenSeriesIDs(for: filter)) }
            }
            var out: [UUID: Set<String>] = [:]
            for await (id, ids) in group { if let ids { out[id] = ids } }
            return out
        }
        guard filter == contentFilter else { return }
        hiddenSeries = loaded
    }

    /// Series from local data that the active profile may see. Anything
    /// built from saved series (Favorites, Top Shelf) goes through this.
    func visibleSeries(_ series: [SeriesSummary]) -> [SeriesSummary] {
        ContentVisibility.visible(series, filter: contentFilter, hidden: hiddenSeries)
    }

    // MARK: Profile PINs

    func hasPIN(_ profile: UUID) -> Bool {
        _ = pinRevision
        return pins.hasPIN(profile: profile)
    }

    /// True when the profile has a PIN that hasn't been entered this session.
    func isLocked(_ profile: UUID) -> Bool { !locks.isUnlocked(profile, store: pins) }

    func requiresPINToOpen(_ profile: UUID) -> Bool { state.requiresPINToOpen(profile: profile) }

    /// Opening this profile asks for its PIN first.
    func needsPINToOpen(_ profile: UUID) -> Bool {
        requiresPINToOpen(profile) && isLocked(profile)
    }

    func setRequiresPINToOpen(_ on: Bool, profile: UUID) {
        update { $0.setRequiresPINToOpen(on, profile: profile) }
    }

    /// Sets a new PIN (the profile stays unlocked) or removes it with nil.
    func setPIN(_ pin: String?, for profile: UUID) {
        pins.setPIN(pin, profile: profile)
        pinRevision += 1
        if pin == nil {
            setRequiresPINToOpen(false, profile: profile)
            locks.lock(profile)
        } else {
            locks.markUnlocked(profile)
        }
    }

    /// Checks a PIN against `candidates`, unlocking the one it matches.
    func attemptPIN(_ pin: String, candidates: [UUID]) -> ProfileLocks.Result {
        locks.attempt(pin, candidates: candidates, store: pins)
    }

    /// Profiles that have a PIN.
    var protectedProfiles: [UUID] { state.profiles.map(\.id).filter { hasPIN($0) } }

    /// Locks every profile again (the app went to the background). Shows
    /// the picker if the active profile needs its PIN to open.
    func lockAll() {
        locks.lockAll()
        if needsPINToOpen(activeProfile.id) { isPickingProfile = true }
    }
}
