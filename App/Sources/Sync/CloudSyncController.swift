import Foundation
import Observation
import MangaCore

/// Runs iCloud sync for the app: on launch, when the app comes back to the
/// foreground, a few seconds after local changes, and when a silent push
/// says another device saved something.
///
/// In builds without an iCloud container (no paid Apple Developer
/// membership yet, CI, sideloading) it uses `LocalOnlySyncStore` and never
/// touches CloudKit; the settings screen explains why sync is off.
@MainActor
@Observable
final class CloudSyncController {
    enum Phase: Equatable {
        /// This build has no iCloud container.
        case notConfigured
        case off
        case checking
        case noAccount
        case restricted
        case syncing
        case upToDate
        case waiting(String)
        case failed(String)
    }

    private(set) var phase: Phase
    private(set) var lastSyncAt: Date?
    private(set) var pendingCount = 0
    let containerIdentifier: String?

    var isAvailableInBuild: Bool { containerIdentifier != nil }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { syncNow() } else { phase = isAvailableInBuild ? .off : .notConfigured }
        }
    }

    static let enabledKey = "mangareader.icloud.enabled"
    @ObservationIgnored private let engine: SyncEngine
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var applyingRemote = false

    init(model: AppModel, containerIdentifier: String? = CloudSyncAvailability.containerIdentifier()) {
        self.model = model
        self.containerIdentifier = containerIdentifier
        let store: SyncStore
        if let containerIdentifier, !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            store = CloudKitSyncStore(containerIdentifier: containerIdentifier)
        } else {
            store = LocalOnlySyncStore()
        }
        let keyValue: KeyValueStore = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            ? InMemoryKeyValueStore() : UserDefaultsStore()
        engine = SyncEngine(store: store, persistence: DefaultSyncPersistence(keyValue: keyValue))
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        phase = containerIdentifier == nil ? .notConfigured : .off
        Task { [engine] in
            let last = await engine.lastSuccessAt
            let pending = await engine.pendingCount
            await MainActor.run {
                self.lastSyncAt = last
                self.pendingCount = pending
            }
        }
    }

    /// Called by `AppModel` after every saved change.
    func stateDidChange() {
        guard isAvailableInBuild, isEnabled, !applyingRemote else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// Syncs now; if a sync is already running, runs once more after it.
    func syncNow() {
        // A guest's state is never synced; the owner's syncs once it ends.
        guard isAvailableInBuild, isEnabled, let model, !model.isGuest else { return }
        if running != nil { again = true; return }
        if phase != .syncing { phase = .checking }
        let host = SyncHost(
            currentState: { await MainActor.run { model.state } },
            apply: { [weak self] patch in
                await MainActor.run {
                    self?.applyingRemote = true
                    defer { self?.applyingRemote = false }
                    return model.applySync(patch)
                }
            })
        running = Task { [engine] in
            do {
                await MainActor.run { self.phase = .syncing }
                let report = try await engine.sync(host: host)
                let last = await engine.lastSuccessAt
                await MainActor.run {
                    self.lastSyncAt = last
                    self.pendingCount = report.pending
                    switch report.status {
                    case .available:
                        self.phase = report.pending > 0 ? .waiting("\(report.pending) changes are waiting to upload.") : .upToDate
                    case .noAccount: self.phase = .noAccount
                    case .restricted: self.phase = .restricted
                    case .notConfigured: self.phase = .notConfigured
                    case .temporarilyUnavailable, .unknown: self.phase = .waiting("iCloud isn't available right now.")
                    }
                }
            } catch {
                let message = await engine.lastError ?? error.localizedDescription
                let pending = await engine.pendingCount
                await MainActor.run {
                    self.pendingCount = pending
                    self.phase = .failed(message)
                }
            }
            await MainActor.run {
                self.running = nil
                if self.again {
                    self.again = false
                    self.syncNow()
                }
            }
        }
    }
}
