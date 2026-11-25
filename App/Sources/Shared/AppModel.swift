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
    @ObservationIgnored var makeClient: (ServerConfig, ServerCredential?, Set<String>?, HTTPTransport) -> MangaServer = {
        MangaServerFactory.make(config: $0, credential: $1, categoryScope: $2, transport: $3)
    }

    init(stateStore: StateStore, secrets: SecretStore, transport: HTTPTransport = URLSessionTransport()) {
        self.stateStore = stateStore
        self.secrets = secrets
        self.transport = transport
        self.state = stateStore.load()
        self.isPickingProfile = state.profiles.count > 1
    }

    static func live() -> AppModel {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let store = StateStore(backing: InMemoryKeyValueStore())
            if let seeded = UITestingSeed.state() { store.save(seeded) }
            let model = AppModel(stateStore: store, secrets: InMemorySecretStore())
            if ProcessInfo.processInfo.arguments.contains("-demoServers") { model.installDemoServers() }
            if ProcessInfo.processInfo.arguments.contains("-mockKomga") { model.installMockKomga() }
            return model
        }
        return AppModel(stateStore: StateStore(backing: UserDefaultsStore()), secrets: KeychainSecretStore())
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
        update { $0.recordProgress(chapter.seriesRef, chapterID: chapter.id, page: page, completed: completed, profile: profile) }
        guard syncsProgress(to: chapter.seriesRef.serverID), let client = client(for: chapter.seriesRef) else { return }
        try? await client.saveProgress(chapter: chapter, libraryID: libraryID, page: page, completed: completed)
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
}
