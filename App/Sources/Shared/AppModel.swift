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

    init(stateStore: StateStore, secrets: SecretStore, transport: HTTPTransport = URLSessionTransport()) {
        self.stateStore = stateStore
        self.secrets = secrets
        self.transport = transport
        self.state = stateStore.load()
    }

    static func live() -> AppModel {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return AppModel(stateStore: StateStore(backing: InMemoryKeyValueStore()), secrets: InMemorySecretStore())
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

    // MARK: Servers

    /// A client for a server, signed in as the active profile.
    func client(for server: ServerConfig) -> MangaServer {
        let key = "\(activeProfile.id.uuidString)|\(server.id.uuidString)|\(server.baseURL.absoluteString)"
        if let cached = clientCache[key] { return cached }
        let credential = secrets.credential(profile: activeProfile.id, server: server.id)
        let client = MangaServerFactory.make(config: server, credential: credential, transport: transport)
        clientCache[key] = client
        return client
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
}
