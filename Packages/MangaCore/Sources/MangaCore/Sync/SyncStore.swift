import Foundation

/// Where synced records live off the device. `CloudKitSyncStore` talks to
/// the user's private iCloud database; tests use `InMemoryCloudStore`; a
/// future backend (another cloud, a server) only has to implement this.
///
/// Every method may throw `SyncStoreError`.
public protocol SyncStore: Sendable {
    /// Whether there's an account to sync with. `userID` changes when the
    /// person signs in to a different account.
    func accountStatus() async throws -> SyncAccountStatus
    /// Creates whatever the store needs (zone, push subscription). Called
    /// once, and again after `SyncStoreError.zoneMissing`.
    func prepare() async throws
    /// Records changed since `token` (nil = everything). Call again with the
    /// returned token while `moreComing` is true.
    func fetchChanges(since token: Data?) async throws -> SyncChangeBatch
    /// Saves records. A record another device changed since this device
    /// last saw it comes back as `.conflict` with the stored version.
    func save(_ records: [SyncRecord]) async throws -> [String: SyncSaveOutcome]
    /// Forgets anything cached about the account (after it changed).
    func reset() async
}

public extension SyncStore {
    func reset() async {}
}

public enum SyncAccountStatus: Sendable, Equatable {
    /// This build can't sync (no iCloud container; see docs/ICLOUD.md).
    case notConfigured
    case available(userID: String?)
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unknown
}

public struct SyncChangeBatch: Sendable {
    public var records: [SyncRecord]
    public var token: Data?
    public var moreComing: Bool

    public init(records: [SyncRecord], token: Data?, moreComing: Bool = false) {
        self.records = records
        self.token = token
        self.moreComing = moreComing
    }
}

public enum SyncSaveOutcome: Sendable, Equatable {
    case saved(SyncRecord)
    case conflict(SyncRecord)
    case failed(String)
}

public enum SyncStoreError: Error, Equatable, Sendable {
    /// The change token is too old; fetch everything again.
    case tokenExpired
    /// The zone is gone (e.g. the person deleted the app's iCloud data).
    case zoneMissing
    case notSignedIn
    case network
    case quotaExceeded
    case other(String)
}

/// The default when the build has no iCloud: never syncs, never fails.
/// State stays on the device (and in Wi-Fi backups).
public struct LocalOnlySyncStore: SyncStore {
    public init() {}
    public func accountStatus() async throws -> SyncAccountStatus { .notConfigured }
    public func prepare() async throws {}
    public func fetchChanges(since token: Data?) async throws -> SyncChangeBatch { SyncChangeBatch(records: [], token: token) }
    public func save(_ records: [SyncRecord]) async throws -> [String: SyncSaveOutcome] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.key, .failed("iCloud isn't set up in this build")) })
    }
}

/// The same `SyncStore` contract held in memory: a fake iCloud for tests
/// and previews. Several `client()`s share one database, like devices on one
/// iCloud account, each with its own view of which versions it has seen.
public final class InMemoryCloudStore: @unchecked Sendable {
    struct Stored { var record: SyncRecord; var tag: Int; var seq: Int }

    private let lock = NSLock()
    private var records: [String: Stored] = [:]
    private var seq = 0
    private var tag = 0
    public var status: SyncAccountStatus = .available(userID: "user-1")
    /// Makes the next calls fail, e.g. `.network`.
    public var failure: SyncStoreError?
    /// Oldest token still accepted; older ones get `.tokenExpired`.
    public var minimumToken = 0
    /// Makes saves (only) fail, e.g. to test the offline queue.
    public var saveFailure: SyncStoreError?
    /// Runs at the start of every save, e.g. to simulate another device
    /// saving between this device's fetch and save.
    public var beforeSave: (() -> Void)?
    public private(set) var saveCalls = 0

    public init() {}

    public func client() -> Client { Client(cloud: self) }

    public var all: [SyncRecord] {
        lock.lock(); defer { lock.unlock() }
        return records.values.map(\.record).sorted { $0.key < $1.key }
    }

    public func record(_ key: String) -> SyncRecord? {
        lock.lock(); defer { lock.unlock() }
        return records[key]?.record
    }

    /// Writes as some other device would, bumping the version.
    public func put(_ record: SyncRecord) {
        lock.lock(); defer { lock.unlock() }
        seq += 1; tag += 1
        records[record.key] = Stored(record: record, tag: tag, seq: seq)
    }

    public func wipe() {
        lock.lock(); defer { lock.unlock() }
        records = [:]
    }

    public final class Client: SyncStore, @unchecked Sendable {
        let cloud: InMemoryCloudStore
        private let lock = NSLock()
        /// The version of each record this client last saw.
        private var seen: [String: Int] = [:]
        public private(set) var prepared = 0

        init(cloud: InMemoryCloudStore) { self.cloud = cloud }

        private func check() throws {
            if let f = cloud.failure { throw f }
        }

        public func accountStatus() async throws -> SyncAccountStatus {
            try check()
            return cloud.status
        }

        public func prepare() async throws {
            try check()
            prepared += 1
        }

        public func fetchChanges(since token: Data?) async throws -> SyncChangeBatch {
            try check()
            let since = token.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            if token != nil && since < cloud.minimumToken { throw SyncStoreError.tokenExpired }
            let changed = cloud.records.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
            lock.lock()
            for s in changed { seen[s.record.key] = s.tag }
            lock.unlock()
            return SyncChangeBatch(records: changed.map(\.record), token: Data(String(cloud.seq).utf8))
        }

        public func save(_ records: [SyncRecord]) async throws -> [String: SyncSaveOutcome] {
            try check()
            if let f = cloud.saveFailure { throw f }
            if let hook = cloud.beforeSave {
                cloud.beforeSave = nil
                hook()
            }
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            cloud.saveCalls += 1
            lock.lock(); defer { lock.unlock() }
            var out: [String: SyncSaveOutcome] = [:]
            for r in records {
                if let stored = cloud.records[r.key], stored.tag != seen[r.key] {
                    seen[r.key] = stored.tag
                    out[r.key] = .conflict(stored.record)
                    continue
                }
                cloud.seq += 1; cloud.tag += 1
                cloud.records[r.key] = Stored(record: r, tag: cloud.tag, seq: cloud.seq)
                seen[r.key] = cloud.tag
                out[r.key] = .saved(r)
            }
            return out
        }

        public func reset() async {
            lock.lock(); defer { lock.unlock() }
            seen = [:]
        }
    }
}
