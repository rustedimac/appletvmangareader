import Foundation
@testable import MangaCore

/// One simulated device: its own AppState, logins, sync engine and view of
/// the shared fake iCloud.
final class SyncTestDevice: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: AppState
    let secrets = InMemorySecretStore()
    let persistence: InMemorySyncPersistence
    let client: InMemoryCloudStore.Client
    var engine: SyncEngine
    var clock: Date

    init(cloud: InMemoryCloudStore, state: AppState = .initial(), deviceID: String,
         start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        _state = state
        clock = start
        persistence = InMemorySyncPersistence()
        persistence.journal = SyncJournal(deviceID: deviceID)
        client = cloud.client()
        engine = SyncEngine(store: client, persistence: persistence, now: { Date() })
        engine = SyncEngine(store: client, persistence: persistence, now: { [unowned self] in self.now })
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return clock
    }

    func advance(_ seconds: TimeInterval = 60) {
        lock.lock(); clock += seconds; lock.unlock()
    }

    var state: AppState {
        get { lock.lock(); defer { lock.unlock() }; return _state }
        set { lock.lock(); _state = newValue; lock.unlock() }
    }

    func change(_ body: (inout AppState) -> Void) {
        lock.lock(); body(&_state); lock.unlock()
    }

    var host: SyncHost {
        SyncHost(currentState: { [unowned self] in self.state },
                 apply: { [unowned self] patch in
                     var s = self.state
                     let effects = SyncMapper.apply(patch, to: &s)
                     self.state = s
                     effects.applyCredentials(to: self.secrets, servers: s.servers.map(\.id), profiles: s.profiles.map(\.id))
                     return effects
                 })
    }

    @discardableResult
    func sync() async throws -> SyncReport {
        try await engine.sync(host: host)
    }

    /// Simulates relaunching the app (engine reloads persisted sync state).
    func relaunch() {
        engine = SyncEngine(store: client, persistence: persistence, now: { [unowned self] in self.now })
    }

    var profile: UUID { state.activeProfile!.id }
}

enum SyncFixtures {
    static let kavitaURL = URL(string: "http://kavita.example:5000")!
    static let suwayomiURL = URL(string: "http://suwayomi.example:4567")!

    static func series(_ server: UUID, _ id: String, _ title: String = "Fictional Series") -> SeriesSummary {
        SeriesSummary(ref: SeriesRef(serverID: server, seriesID: id), title: title, coverURL: nil, libraryID: "1")
    }

    /// A state with one profile, one Kavita server, a favorite and progress.
    static func populated() -> AppState {
        var s = AppState.initial()
        let server = ServerConfig(kind: .kavita, name: "Home Kavita", baseURL: kavitaURL)
        s.addServer(server)
        let p = s.activeProfile!.id
        s.setFavorite(series(server.id, "1", "Star Harbor"), true, profile: p, now: Date(timeIntervalSince1970: 1_700_000_000))
        s.recordProgress(SeriesRef(serverID: server.id, seriesID: "1"), chapterID: "c1", page: 20, completed: true,
                         profile: p, now: Date(timeIntervalSince1970: 1_700_000_050))
        s.recordProgress(SeriesRef(serverID: server.id, seriesID: "1"), chapterID: "c2", page: 4, completed: false,
                         profile: p, now: Date(timeIntervalSince1970: 1_700_000_100))
        return s
    }
}
