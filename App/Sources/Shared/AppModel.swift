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
    @ObservationIgnored let transport: HTTPTransport
    @ObservationIgnored private var clientCache: [String: MangaServer] = [:]
    /// True while the "Who's reading?" picker is showing. Set at launch when
    /// there's more than one profile, and by "Switch Profile" in Settings.
    var isPickingProfile = false
    /// Builds server clients, limited to a set of library/category ids (nil
    /// for all). UI tests swap in `SampleLibraryServer` (see
    /// `AppModel+Demo.swift`).
    /// Called after every saved change; iCloud sync listens here.
    @ObservationIgnored var onStateChange: (@MainActor () -> Void)?
    @ObservationIgnored var makeClient: (ServerConfig, ServerCredential?, Set<String>?, HTTPTransport) -> MangaServer = {
        MangaServerFactory.make(config: $0, credential: $1, categoryScope: $2, transport: $3)
    }
    /// Signs in to Kavita with a username and password and returns the
    /// login to keep (an auth key, never the password). UI tests swap in a
    /// fake (see `AppModel+Demo.swift`).
    @ObservationIgnored var kavitaSignIn: (ServerConfig, String, String, HTTPTransport) async throws -> ServerCredential = {
        try await KavitaClient.signIn(baseURL: $0.baseURL, username: $1, password: $2, transport: $3)
    }

    /// The app runs as the current Apple TV user, so `state` belongs to that
    /// user alone. See `AppleTVUsers/AppleTVUsers.swift`.
    @ObservationIgnored let perAppleTVUser: Bool
    /// Servers shared by every Apple TV user. Nil unless `perAppleTVUser`.
    @ObservationIgnored let sharedServers: SharedServerStore?
    /// Called after every saved change (Top Shelf refresh, shared servers).
    @ObservationIgnored var stateObservers: [(_ old: AppState, _ new: AppState) -> Void] = []

    init(stateStore: StateStore, secrets: SecretStore, transport: HTTPTransport = URLSessionTransport(),
         identity: DeviceUserIdentity = SingleUserDevice(), sharedServers: SharedServerStore? = nil) {
        self.stateStore = stateStore
        let perAppleTVUser = identity.separatesAppDataPerUser
        self.perAppleTVUser = perAppleTVUser
        self.sharedServers = perAppleTVUser ? sharedServers : nil
        if perAppleTVUser, let sharedServers {
            self.secrets = SharedFallbackSecretStore(local: secrets, shared: sharedServers)
        } else {
            self.secrets = secrets
        }
        self.transport = transport
        self.state = stateStore.load()
        let launch = ProfileLaunch.decide(state, perSystemUser: perAppleTVUser)
        if let id = launch.profileID, id != state.activeProfileID { state.setActiveProfile(id) }
        self.isPickingProfile = launch.showsPicker
        adoptSharedServers()
    }

    static func live() -> AppModel {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let store = StateStore(backing: InMemoryKeyValueStore())
            if let seeded = UITestingSeed.state() { store.save(seeded) }
            let model = AppModel(stateStore: store, secrets: InMemorySecretStore(),
                                 identity: FixedDeviceUserIdentity(separatesAppDataPerUser: UITestingSeed.perAppleTVUser),
                                 sharedServers: InMemorySharedServerStore(UITestingSeed.sharedServers()))
            if ProcessInfo.processInfo.arguments.contains("-demoServers") { model.installDemoServers() }
            if ProcessInfo.processInfo.arguments.contains("-mockKomga") { model.installMockKomga() }
            if ProcessInfo.processInfo.arguments.contains("-mockOPDS") { model.installMockOPDS() }
            if ProcessInfo.processInfo.arguments.contains("-demoFavorites") { model.installDemoFavoritesAndBookmarks() }
            if ProcessInfo.processInfo.arguments.contains("-freeLibrary") { model.installFreeLibraryDemo() }
            if ProcessInfo.processInfo.arguments.contains("-liveServers") { model.installLiveServersFromEnvironment() }
            model.applyUITestingHomeLayout()
            return model
        }
        let model = AppModel(stateStore: StateStore(backing: UserDefaultsStore()), secrets: KeychainSecretStore(),
                             identity: AppleTVUserIdentity(),
                             sharedServers: KeychainSharedServerStore())
        model.installFreeLibraryIfNeeded()
        return model
    }

    // MARK: State

    /// The only way to change persisted state. Saves after every change.
    func update(_ change: (inout AppState) -> Void) {
        let old = state
        change(&state)
        stateStore.save(state)
        for observer in stateObservers { observer(old, state) }
        onStateChange?()
    }

    /// Drops cached server clients, e.g. after sync changed servers or logins.
    func resetClients() {
        clientCache.removeAll()
    }

    var activeProfile: Profile { state.activeProfile ?? Profile(name: "Me") }
    var servers: [ServerConfig] { state.servers }

    func switchProfile(_ id: UUID) {
        update { $0.setActiveProfile(id) }
        clientCache.removeAll()
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
        update { $0.removeProfile(id) }
        clientCache.removeAll()
    }

    // MARK: Servers

    /// A client for a server, signed in as the active profile and limited to
    /// the libraries/categories that profile imports.
    func client(for server: ServerConfig) -> MangaServer {
        let scope = selectedCategories(for: server)
        let key = "\(activeProfile.id.uuidString)|\(server.id.uuidString)|\(server.baseURL.absoluteString)|\(Self.scopeKey(scope))"
        if let cached = clientCache[key] { return cached }
        let credential = secrets.credential(profile: activeProfile.id, server: server.id)
        let client = makeClient(server, credential, scope, transport)
        clientCache[key] = client
        return client
    }

    /// A stable string for a selection, for cache keys and `.task(id:)`.
    static func scopeKey(_ scope: Set<String>?) -> String {
        scope.map { "only:" + $0.sorted().joined(separator: ",") } ?? "all"
    }

    /// Changes whenever the active profile's selection for `server` does.
    func scopeKey(for server: ServerConfig) -> String {
        Self.scopeKey(selectedCategories(for: server))
    }

    func client(for ref: SeriesRef) -> MangaServer? {
        state.server(ref.serverID).map(client(for:))
    }

    func credential(for server: ServerConfig) -> ServerCredential? {
        secrets.credential(profile: activeProfile.id, server: server.id)
    }

    /// Saves a server and the active profile's login for it. Throws when
    /// the login couldn't be stored (it's read back to check), so the form
    /// stays open with the error rather than closing as if it had saved.
    func saveServer(_ server: ServerConfig, credential: ServerCredential?) throws {
        // Store the login first: a failed write leaves the server list as it was.
        try secrets.saveCredential(credential, profile: activeProfile.id, server: server.id)
        if state.server(server.id) == nil {
            update { $0.addServer(server) }
        } else {
            update { $0.updateServer(server) }
        }
        // Now that a new server is in the shared directory, offer the login
        // as the one other Apple TV users fall back to.
        if let credential, secrets is SharedFallbackSecretStore {
            secrets.setCredential(credential, profile: activeProfile.id, server: server.id)
        }
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

    /// Turns the server form into the login to save: signs in to Kavita
    /// when a password was typed, names the owner of a pasted Kavita key,
    /// and works out how a Suwayomi server takes a username and password.
    func resolveCredential(_ draft: ServerDraft, for server: ServerConfig) async throws -> ServerCredential? {
        if draft.needsKavitaSignIn {
            return try await kavitaSignIn(server, draft.username, draft.password, transport)
        }
        guard var credential = draft.credential else { return nil }
        switch server.kind {
        case .kavita:
            if credential.username == nil, let kavita = makeClient(server, credential, nil, transport) as? KavitaClient {
                credential.username = try await kavita.username()
            }
        case .suwayomi:
            if credential.suwayomiLogin == nil, let user = credential.username {
                credential.suwayomiLogin = await SuwayomiClient.detectLoginMode(
                    config: server, username: user, password: credential.password ?? "", transport: transport)
            }
        case .komga, .opds, .freeLibrary:
            break
        }
        return credential
    }

    /// The Suwayomi user a login maps to, on servers with user accounts.
    /// Nil when the server keeps one shared progress.
    func suwayomiUser(_ server: ServerConfig, credential: ServerCredential?) async -> String? {
        guard server.kind == .suwayomi, let client = makeClient(server, credential, nil, transport) as? SuwayomiClient else {
            return nil
        }
        return await client.currentUser()
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
        if server.kind == .freeLibrary {
            update { $0.removeFreeLibrary() }
        } else {
            update { $0.removeServer(server.id) }
        }
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
        // The Free Library has no server progress; it's always kept here.
        if serverID == FreeLibrary.serverID { return false }
        return state.serverSettings(profile: activeProfile.id, server: serverID).syncProgressToServer
    }

    /// Writes the reader's position to this profile's saved state only. The
    /// reader calls it on every page change so a crash or a force quit
    /// never loses the page; `recordProgress` pushes to the server.
    func recordLocalProgress(chapter: Chapter, series: SeriesSummary, page: Int, completed: Bool) {
        let profile = activeProfile.id
        update { $0.recordProgress(chapter.seriesRef, chapterID: chapter.id, page: page, completed: completed,
                                   profile: profile, series: series) }
    }

    /// The page to open `chapter` at when none was asked for.
    func resumePage(for chapter: Chapter, sessionPage: Int?) -> Int {
        ResumePosition.startPage(for: chapter, sessionPage: sessionPage,
                                 local: state.progress(chapter.seriesRef, profile: activeProfile.id),
                                 serverReadAt: chapter.lastReadAt)
    }

    /// Records progress locally, and on the server if this profile syncs
    /// there. A change the server doesn't confirm stays queued on the
    /// series and is retried by `seriesDetail` / `syncPendingProgress`.
    func recordProgress(chapter: Chapter, series: SeriesSummary, page: Int, completed: Bool) async {
        let profile = activeProfile.id
        let ref = chapter.seriesRef
        unreadCountOverrides[ref] = nil
        let now = Date()
        let syncs = syncsProgress(to: ref.serverID)
        update {
            $0.recordProgress(ref, chapterID: chapter.id, page: page, completed: completed, profile: profile,
                              now: now, series: series)
            if syncs {
                $0.queuePending(PendingProgress(chapterID: chapter.id, page: page, completed: completed, at: now),
                                for: ref, profile: profile)
            }
        }
        guard syncs, let client = client(for: ref) else { return }
        do {
            try await client.saveProgress(chapter: chapter, libraryID: series.libraryID, page: page, completed: completed)
            update { $0.clearPending(ref, chapterIDs: [chapter.id], through: now, profile: profile) }
        } catch {
            // Stays queued.
        }
    }

    /// Poster badge counts changed by "Mark as Unread" since the feeds
    /// loaded, so posters update without reloading every row.
    private(set) var unreadCountOverrides: [SeriesRef: Int] = [:]
    /// Chapter counts for poster captions (see `SeriesCountStore`).
    let seriesCounts = SeriesCountStore()

    func unreadCount(for series: SeriesSummary) -> Int? {
        unreadCountOverrides[series.ref] ?? series.unreadCount
    }

    /// Marks chapters of one series unread for this profile, and on the
    /// server when this profile syncs there.
    func markUnread(_ chapters: [Chapter], in ref: SeriesRef) async throws {
        guard !chapters.isEmpty else { return }
        let profile = activeProfile.id
        let ids = Set(chapters.map(\.id))
        update {
            $0.markUnread(ref, chapterIDs: ids, profile: profile)
            // A queued push would mark them read again.
            $0.clearPending(ref, chapterIDs: ids, through: .distantFuture, profile: profile)
        }
        if syncsProgress(to: ref.serverID), let client = client(for: ref) {
            try await client.markUnread(chapters: chapters)
        }
        await refreshUnreadCount(ref)
    }

    /// Marks chapters of one series read for this profile, and on the
    /// server when this profile syncs there. Where Continue resumes stays
    /// the same; it skips read chapters on its own.
    func markRead(_ chapters: [Chapter], in ref: SeriesRef, libraryID: String?) async throws {
        guard !chapters.isEmpty else { return }
        let profile = activeProfile.id
        let ids = Set(chapters.map(\.id))
        update {
            $0.markRead(ref, chapterIDs: ids, profile: profile)
            // A queued partial-page push would undo the read mark.
            $0.clearPending(ref, chapterIDs: ids, through: .distantFuture, profile: profile)
        }
        if syncsProgress(to: ref.serverID), let client = client(for: ref) {
            try await client.markRead(chapters: chapters, libraryID: libraryID)
        }
        await refreshUnreadCount(ref)
    }

    /// Marks every chapter of a series unread for this profile, and on the
    /// server when this profile syncs there.
    func markSeriesUnread(_ ref: SeriesRef) async throws {
        let profile = activeProfile.id
        // Also drops any queued pushes for the series.
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

    /// Series detail with progress resolved for this profile: local
    /// progress on top when it doesn't sync to the server; otherwise the
    /// server's, merged with any queued local changes (latest wins), which
    /// are pushed.
    func seriesDetail(_ ref: SeriesRef) async throws -> SeriesDetail {
        guard let client = client(for: ref) else { throw MangaError.notFound }
        let detail = try await client.seriesDetail(ref.seriesID)
        let profile = activeProfile.id
        guard syncsProgress(to: ref.serverID) else {
            return state.applyingLocalProgress(to: detail, profile: profile)
        }
        let pending = state.pending(ref, profile: profile)
        guard !pending.isEmpty else { return detail }
        let resolution = ProgressSync.reconcile(detail, pending: pending)
        if !resolution.dropped.isEmpty {
            update { state in
                for p in resolution.dropped {
                    state.clearPending(ref, chapterIDs: [p.chapterID], through: p.at, profile: profile)
                }
            }
        }
        for p in resolution.push {
            guard let chapter = resolution.detail.chapters.first(where: { $0.id == p.chapterID }) else { continue }
            do {
                try await client.saveProgress(chapter: chapter, libraryID: detail.summary.libraryID,
                                              page: p.page, completed: p.completed)
                update { $0.clearPending(ref, chapterIDs: [p.chapterID], through: p.at, profile: profile) }
            } catch {
                break // Still offline; try again later.
            }
        }
        return resolution.detail
    }

    /// Pushes queued progress for every series on servers this profile
    /// syncs to. Home calls it before loading its rows.
    func syncPendingProgress() async {
        let profile = activeProfile.id
        for server in servers where syncsProgress(to: server.id) {
            for ref in state.seriesWithPending(server: server.id, profile: profile) {
                guard activeProfile.id == profile else { return }
                if (try? await seriesDetail(ref)) == nil { break } // Server unreachable.
            }
        }
    }

    /// This profile's own Continue Reading for a server it doesn't sync to.
    func localContinueReading(for server: ServerConfig) -> [SeriesSummary] {
        state.localContinueReading(server: server.id, profile: activeProfile.id)
    }

    // MARK: Reader settings

    func readerSettings(for ref: SeriesRef) -> ReaderSettings {
        let settings = state.readerSettings(for: ref, profile: activeProfile.id)
        if ref.serverID == FreeLibrary.serverID, !state.hasReaderOverride(for: ref, profile: activeProfile.id) {
            return FreeLibrary.readerSettings(from: settings)
        }
        return settings
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
}
