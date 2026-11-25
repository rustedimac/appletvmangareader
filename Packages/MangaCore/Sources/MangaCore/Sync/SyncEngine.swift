import Foundation

/// Reads and changes the app's state for the engine. The app's version
/// hops to the main actor and saves through `AppModel.update`.
public struct SyncHost: Sendable {
    public var currentState: @Sendable () async -> AppState
    public var apply: @Sendable (SyncPatch) async -> SyncApplyEffects

    public init(currentState: @escaping @Sendable () async -> AppState,
                apply: @escaping @Sendable (SyncPatch) async -> SyncApplyEffects) {
        self.currentState = currentState
        self.apply = apply
    }
}

/// What this device last agreed with the cloud. Rebuildable: if it's lost
/// (tvOS may purge caches) the next sync is treated as a first sync, and
/// cloud values win over unchanged local ones.
public struct SyncLedger: Codable, Sendable, Equatable {
    public var changeToken: Data?
    public var accountID: String?
    public var zonePrepared = false
    /// The last version of each record both sides agree on.
    public var synced: [String: SyncRecord] = [:]

    public init() {}

    public var isFresh: Bool { changeToken == nil && synced.isEmpty }
}

/// Small, must-keep sync state: the device id and the offline queue of
/// changes not yet in the cloud.
public struct SyncJournal: Codable, Sendable, Equatable {
    public var deviceID: String
    public var pending: [String: SyncRecord] = [:]
    public var lastSuccessAt: Date?
    public var lastError: String?

    public init(deviceID: String = UUID().uuidString) {
        self.deviceID = deviceID
    }
}

public protocol SyncPersistence: Sendable {
    func loadLedger() -> SyncLedger
    func saveLedger(_ ledger: SyncLedger)
    func loadJournal() -> SyncJournal?
    func saveJournal(_ journal: SyncJournal)
}

/// The ledger goes in a Caches file (it can be large and is rebuildable);
/// the journal goes in the `KeyValueStore` beside `AppState`, because the
/// offline queue must survive.
public final class DefaultSyncPersistence: SyncPersistence, @unchecked Sendable {
    public static let journalKey = "mangareader.sync.journal.v1"
    let ledgerURL: URL
    let keyValue: KeyValueStore

    public init(keyValue: KeyValueStore, ledgerURL: URL? = nil) {
        self.keyValue = keyValue
        self.ledgerURL = ledgerURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iCloudSyncLedger.json")
    }

    public func loadLedger() -> SyncLedger {
        (try? Data(contentsOf: ledgerURL)).flatMap { try? JSONDecoder().decode(SyncLedger.self, from: $0) } ?? SyncLedger()
    }

    public func saveLedger(_ ledger: SyncLedger) {
        try? FileManager.default.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(ledger).write(to: ledgerURL, options: .atomic)
    }

    public func loadJournal() -> SyncJournal? {
        keyValue.data(forKey: Self.journalKey).flatMap { try? JSONDecoder().decode(SyncJournal.self, from: $0) }
    }

    public func saveJournal(_ journal: SyncJournal) {
        keyValue.set(try? JSONEncoder().encode(journal), forKey: Self.journalKey)
    }
}

public final class InMemorySyncPersistence: SyncPersistence, @unchecked Sendable {
    private let lock = NSLock()
    public var ledger = SyncLedger()
    public var journal: SyncJournal?

    public init() {}

    public func loadLedger() -> SyncLedger { lock.lock(); defer { lock.unlock() }; return ledger }
    public func saveLedger(_ ledger: SyncLedger) { lock.lock(); defer { lock.unlock() }; self.ledger = ledger }
    public func loadJournal() -> SyncJournal? { lock.lock(); defer { lock.unlock() }; return journal }
    public func saveJournal(_ journal: SyncJournal) { lock.lock(); defer { lock.unlock() }; self.journal = journal }
}

public struct SyncReport: Sendable, Equatable {
    public var status: SyncAccountStatus
    /// Records written into local state.
    public var downloaded = 0
    public var uploaded = 0
    public var conflicts = 0
    /// Changes still waiting to upload (offline queue).
    public var pending = 0
    public var effects = SyncApplyEffects()

    public init(status: SyncAccountStatus) {
        self.status = status
    }
}

/// Two-way sync between `AppState` and a `SyncStore`.
///
/// Each run: fetch what changed in the cloud, work out what changed here
/// since the last run (by comparing with the ledger), merge per record,
/// apply the cloud's side locally, then upload this device's side. A save
/// that races another device comes back as a conflict, is merged with the
/// newer cloud version and saved again. Anything that can't be uploaded
/// stays in the journal's offline queue with its original timestamp.
public actor SyncEngine {
    let store: SyncStore
    let persistence: SyncPersistence
    let now: @Sendable () -> Date
    private(set) var ledger: SyncLedger
    private(set) var journal: SyncJournal
    static let batchSize = 200

    public init(store: SyncStore, persistence: SyncPersistence, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.persistence = persistence
        self.now = now
        ledger = persistence.loadLedger()
        if let j = persistence.loadJournal() {
            journal = j
        } else {
            journal = SyncJournal()
            persistence.saveJournal(journal)
        }
    }

    public var lastSuccessAt: Date? { journal.lastSuccessAt }
    public var lastError: String? { journal.lastError }
    public var pendingCount: Int { journal.pending.count }
    public var deviceID: String { journal.deviceID }

    public func accountStatus() async -> SyncAccountStatus {
        (try? await store.accountStatus()) ?? .unknown
    }

    /// Forgets what was synced, so the next run is a first sync again.
    public func resetLedger() async {
        ledger = SyncLedger()
        persist()
        await store.reset()
    }

    private func persist() {
        persistence.saveLedger(ledger)
        persistence.saveJournal(journal)
    }

    @discardableResult
    public func sync(host: SyncHost) async throws -> SyncReport {
        let status = try await store.accountStatus()
        guard case .available(let userID) = status else { return SyncReport(status: status) }
        if let userID, let known = ledger.accountID, known != userID {
            // A different iCloud account: start over, and don't send the
            // previous account's queued changes to this one.
            ledger = SyncLedger()
            journal.pending = [:]
            await store.reset()
        }
        if let userID { ledger.accountID = userID }
        do {
            let report = try await run(host: host, status: status)
            journal.lastError = report.pending > 0 ? "\(report.pending) changes are waiting to upload." : nil
            if report.pending == 0 { journal.lastSuccessAt = now() }
            persist()
            return report
        } catch {
            journal.lastError = Self.describe(error)
            persist()
            throw error
        }
    }

    static func describe(_ error: Error) -> String {
        switch error as? SyncStoreError {
        case .network?: return "Can't reach iCloud. Changes will upload when the connection is back."
        case .notSignedIn?: return "Not signed in to iCloud."
        case .quotaExceeded?: return "iCloud storage is full."
        case .tokenExpired?, .zoneMissing?: return "iCloud data was reset. Sync will start over."
        case .other(let message)?: return message
        case nil: return error.localizedDescription
        }
    }

    private func run(host: SyncHost, status: SyncAccountStatus) async throws -> SyncReport {
        var report = SyncReport(status: status)
        if !ledger.zonePrepared {
            try await store.prepare()
            ledger.zonePrepared = true
            persist()
        }
        let joining = ledger.isFresh

        // 1. What changed in the cloud.
        var remote: [String: SyncRecord] = [:]
        var token = ledger.changeToken
        var restarts = 0
        while true {
            do {
                let batch = try await store.fetchChanges(since: token)
                for r in batch.records { remote[r.key] = r }
                token = batch.token
                if !batch.moreComing { break }
            } catch SyncStoreError.tokenExpired where restarts < 2 {
                restarts += 1
                token = nil
                remote = [:]
            } catch SyncStoreError.zoneMissing where restarts < 2 {
                restarts += 1
                try await store.prepare()
                token = nil
                remote = [:]
                ledger.synced = [:] // the cloud is empty: upload everything again
            }
        }

        // 2. A device joining sync adopts the cloud's ids for servers and
        // profiles it already has.
        var state = await host.currentState()
        if joining {
            let remap = SyncRemap.matching(incoming: Array(remote.values), local: state)
            if !remap.isEmpty {
                report.effects.add(await host.apply(SyncPatch(remap: remap)))
                state = await host.currentState()
            }
        }

        // 3. What changed here, and the merge.
        let reference = ledger.synced.merging(journal.pending) { _, pending in pending }
        let local = SyncMerge.localRecords(state: state, reference: reference, deviceID: journal.deviceID,
                                           now: now(), joining: joining)
        let dirty = Set(local.compactMap { key, record in
            ledger.synced[key].map { SyncMerge.sameContent($0, record) } == true ? nil : key
        })

        var toApply: [SyncRecord] = []
        var toUpload: [String: SyncRecord] = [:]
        for key in Set(remote.keys).union(dirty) {
            let l = local[key], r = remote[key]
            if let l, let r, dirty.contains(key) {
                // A value this device never synced, without a date of its
                // own, never beats what's already in the cloud.
                let merged = l.modifiedAt == .distantPast && l.kind != .progress ? r : SyncMerge.merge(l, r)
                if !SyncMapper.samePayload(merged.kind, merged.payload, l.payload) { toApply.append(merged) }
                if SyncMerge.sameContent(merged, r) {
                    ledger.synced[key] = r
                    journal.pending[key] = nil
                } else {
                    toUpload[key] = merged
                }
            } else if let r {
                if SyncMapper.canRead(r), !(l == nil && r.isDeleted),
                   !SyncMapper.samePayload(r.kind, l?.payload, r.payload) {
                    toApply.append(r)
                }
                ledger.synced[key] = r
                journal.pending[key] = nil
            } else if let l {
                toUpload[key] = l
            }
        }

        // 4. Cloud changes into local state; then queue this device's side
        // before trying to send it, so a failure loses nothing.
        if !toApply.isEmpty {
            report.effects.add(await host.apply(SyncPatch(records: toApply)))
            report.downloaded += toApply.count
        }
        ledger.changeToken = token
        let stamp = now()
        for (key, record) in toUpload {
            // Nothing in the cloud to defer to: this value is now the newest.
            var record = record
            if record.modifiedAt == .distantPast { record.modifiedAt = stamp }
            toUpload[key] = record
            journal.pending[key] = record
        }
        persist()

        // 5. Upload, merging and retrying conflicts.
        var queue = toUpload
        var round = 0
        while !queue.isEmpty && round < 3 {
            round += 1
            var retry: [String: SyncRecord] = [:]
            var conflictApply: [SyncRecord] = []
            let sorted = queue.values.sorted { $0.key < $1.key }
            for start in stride(from: 0, to: sorted.count, by: Self.batchSize) {
                let chunk = Array(sorted[start..<min(start + Self.batchSize, sorted.count)])
                let results = try await store.save(chunk)
                for record in chunk {
                    switch results[record.key] {
                    case .saved(let saved)?:
                        ledger.synced[record.key] = saved
                        journal.pending[record.key] = nil
                        report.uploaded += 1
                    case .conflict(let server)?:
                        report.conflicts += 1
                        let merged = SyncMerge.merge(record, server)
                        if SyncMapper.canRead(server),
                           !SyncMapper.samePayload(merged.kind, merged.payload, record.payload) {
                            conflictApply.append(merged)
                        }
                        if SyncMerge.sameContent(merged, server) {
                            ledger.synced[record.key] = server
                            journal.pending[record.key] = nil
                        } else {
                            retry[record.key] = merged
                            journal.pending[record.key] = merged
                        }
                    case .failed?, nil:
                        break // stays queued
                    }
                }
                persist()
            }
            if !conflictApply.isEmpty {
                report.effects.add(await host.apply(SyncPatch(records: conflictApply)))
                report.downloaded += conflictApply.count
            }
            queue = retry
        }
        report.pending = journal.pending.count
        return report
    }
}

extension SyncApplyEffects {
    mutating func add(_ other: SyncApplyEffects) {
        credentialMoves += other.credentialMoves
        removedServerIDs.formUnion(other.removedServerIDs)
        removedProfileIDs.formUnion(other.removedProfileIDs)
        appliedCount.merge(other.appliedCount, uniquingKeysWith: +)
    }
}
