#if canImport(CloudKit)
import CloudKit
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// `SyncStore` on the user's private CloudKit database.
///
/// - One custom zone, `MangaReaderSync`, so changes can be fetched with a
///   change token and the zone can be wiped as one unit.
/// - One record type, `SyncRecord`, fields: `key`, `kind`, `payload`
///   (bytes), `modifiedAt`, `deviceID`, `deleted`. The record name is a hash
///   of `key`, so any key fits CloudKit's naming rules.
/// - Saves use `.ifServerRecordUnchanged`, so a save that races another
///   device fails with the server's copy, which the engine merges.
/// - A zone subscription sends silent pushes when another device saves.
///
/// Only create this when `CloudSyncAvailability.containerIdentifier()` says
/// the build has an iCloud container: CloudKit stops the app if it's used
/// without the iCloud entitlement.
public final class CloudKitSyncStore: SyncStore, @unchecked Sendable {
    public static let zoneName = "MangaReaderSync"
    public static let recordType = "SyncRecord"
    public static let subscriptionID = "mangareader-sync-zone-changes"

    let container: CKContainer
    let database: CKDatabase
    let zoneID: CKRecordZone.ID
    let cacheURL: URL
    private let lock = NSLock()
    /// recordName → archived CKRecord system fields (the change tag), so a
    /// save says which version it's replacing.
    private var systemFields: [String: Data]

    public init(containerIdentifier: String, cacheURL: URL? = nil) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iCloudSyncRecordTags.json")
        systemFields = (try? Data(contentsOf: self.cacheURL))
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }

    // MARK: SyncStore

    public func accountStatus() async throws -> SyncAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available:
                let id = try? await container.userRecordID()
                return .available(userID: id?.recordName)
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            case .couldNotDetermine: return .unknown
            @unknown default: return .unknown
            }
        } catch {
            throw Self.map(error)
        }
    }

    public func prepare() async throws {
        do {
            let result = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            if case .failure(let error)? = result.saveResults[zoneID] { throw error }
        } catch {
            throw Self.map(error)
        }
        // Pushes are a bonus (they need the Push Notifications capability);
        // the app also syncs on launch, on wake and after local changes.
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await database.save(subscription)
    }

    public func fetchChanges(since token: Data?) async throws -> SyncChangeBatch {
        let since = token.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
        do {
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: since)
            var records: [SyncRecord] = []
            for (_, outcome) in result.modificationResultsByID {
                guard case .success(let modification) = outcome else { continue }
                remember(modification.record)
                if let r = Self.syncRecord(from: modification.record) { records.append(r) }
            }
            for deletion in result.deletions { forget(deletion.recordID.recordName) }
            saveCache()
            let newToken = try? NSKeyedArchiver.archivedData(withRootObject: result.changeToken, requiringSecureCoding: true)
            return SyncChangeBatch(records: records, token: newToken, moreComing: result.moreComing)
        } catch {
            throw Self.map(error)
        }
    }

    public func save(_ records: [SyncRecord]) async throws -> [String: SyncSaveOutcome] {
        defer { saveCache() }
        return try await saveChunk(records)
    }

    public func reset() async {
        lock.lock()
        systemFields = [:]
        lock.unlock()
        saveCache()
    }

    // MARK: Saving

    private func saveChunk(_ records: [SyncRecord]) async throws -> [String: SyncSaveOutcome] {
        guard !records.isEmpty else { return [:] }
        var byName: [CKRecord.ID: SyncRecord] = [:]
        let ckRecords = records.map { r -> CKRecord in
            let ck = makeRecord(r)
            byName[ck.recordID] = r
            return ck
        }
        let saveResults: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            saveResults = try await database.modifyRecords(saving: ckRecords, deleting: [],
                                                           savePolicy: .ifServerRecordUnchanged, atomically: false).saveResults
        } catch let error as CKError where error.code == .limitExceeded && records.count > 1 {
            let half = records.count / 2
            let first = try await saveChunk(Array(records[..<half]))
            let second = try await saveChunk(Array(records[half...]))
            return first.merging(second) { a, _ in a }
        } catch {
            throw Self.map(error)
        }

        var out: [String: SyncSaveOutcome] = [:]
        for (id, original) in byName {
            switch saveResults[id] {
            case .success(let saved)?:
                remember(saved)
                out[original.key] = .saved(Self.syncRecord(from: saved) ?? original)
            case .failure(let error)?:
                if let ck = error as? CKError, ck.code == .serverRecordChanged, let server = ck.serverRecord {
                    remember(server)
                    out[original.key] = Self.syncRecord(from: server).map { .conflict($0) } ?? .failed("Unreadable iCloud record")
                } else if let ck = error as? CKError, ck.code == .zoneNotFound || ck.code == .userDeletedZone {
                    throw SyncStoreError.zoneMissing
                } else {
                    out[original.key] = .failed(error.localizedDescription)
                }
            case nil:
                out[original.key] = .failed("No result from iCloud")
            }
        }
        return out
    }

    func makeRecord(_ r: SyncRecord) -> CKRecord {
        let name = Self.recordName(for: r.key)
        var record: CKRecord?
        lock.lock()
        let fields = systemFields[name]
        lock.unlock()
        if let fields, let coder = try? NSKeyedUnarchiver(forReadingFrom: fields) {
            coder.requiresSecureCoding = true
            record = CKRecord(coder: coder)
            coder.finishDecoding()
        }
        let ck = record ?? CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        ck["key"] = r.key as CKRecordValue
        ck["kind"] = r.kind.rawValue as CKRecordValue
        ck["payload"] = r.payload.map { $0 as CKRecordValue }
        ck["modifiedAt"] = r.modifiedAt as CKRecordValue
        ck["deviceID"] = r.deviceID as CKRecordValue
        ck["deleted"] = NSNumber(value: r.isDeleted ? 1 : 0)
        return ck
    }

    static func syncRecord(from ck: CKRecord) -> SyncRecord? {
        guard let key = ck["key"] as? String, let kind = ck["kind"] as? String,
              let modifiedAt = ck["modifiedAt"] as? Date else { return nil }
        let deleted = (ck["deleted"] as? NSNumber)?.boolValue ?? false
        return SyncRecord(key: key, kind: SyncKind(kind), payload: deleted ? nil : ck["payload"] as? Data,
                          modifiedAt: modifiedAt, deviceID: ck["deviceID"] as? String ?? "")
    }

    static func recordName(for key: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(key.utf8))
        return "r-" + digest.map { String(format: "%02x", $0) }.joined()
        #else
        return "r-" + Data(key.utf8).base64EncodedString()
        #endif
    }

    // MARK: Change tag cache

    private func remember(_ record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        lock.lock()
        systemFields[record.recordID.recordName] = archiver.encodedData
        lock.unlock()
    }

    private func forget(_ name: String) {
        lock.lock()
        systemFields[name] = nil
        lock.unlock()
    }

    private func saveCache() {
        lock.lock()
        let data = try? JSONEncoder().encode(systemFields)
        lock.unlock()
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data?.write(to: cacheURL, options: .atomic)
    }

    // MARK: Errors

    static func map(_ error: Error) -> Error {
        if error is SyncStoreError { return error }
        guard let ck = error as? CKError else { return SyncStoreError.other(error.localizedDescription) }
        switch ck.code {
        case .changeTokenExpired: return SyncStoreError.tokenExpired
        case .zoneNotFound, .userDeletedZone: return SyncStoreError.zoneMissing
        case .notAuthenticated: return SyncStoreError.notSignedIn
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return SyncStoreError.network
        case .quotaExceeded: return SyncStoreError.quotaExceeded
        case .partialFailure:
            if let first = ck.partialErrorsByItemID?.values.first { return map(first) }
            return SyncStoreError.other(ck.localizedDescription)
        default: return SyncStoreError.other(ck.localizedDescription)
        }
    }
}
#endif
