import Foundation
#if canImport(Security)
import Security
#endif

/// Where non-secret state is persisted. tvOS apps only get durable local
/// storage through UserDefaults (about 1 MB), so state is kept compact.
public protocol KeyValueStore: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    public func set(_ data: Data?, forKey key: String) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func set(_ data: Data?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = data
    }
}

/// Loads and saves `AppState` as JSON. Never throws saved state away: data
/// from any past version is migrated (see `AppStateUpgrade`), and data that
/// can't be read in full is kept under `backupKey` before anything new is
/// saved over it.
public final class StateStore: @unchecked Sendable {
    public static let key = "mangareader.appstate.v1"
    /// The original bytes of state that couldn't be fully read, kept so a
    /// later build can recover them. Never overwritten once set.
    public static let backupKey = "mangareader.appstate.unreadable"
    let backing: KeyValueStore
    /// How the last `load()` went: nil for a fresh install.
    public private(set) var lastLoad: LoadResult?

    public enum LoadResult: Equatable, Sendable {
        case decoded
        /// Some entries were unreadable and left out (original backed up).
        case salvaged
        /// Nothing could be read; started fresh (original backed up).
        case unreadable
    }

    public init(backing: KeyValueStore) {
        self.backing = backing
    }

    public func load() -> AppState {
        guard let data = backing.data(forKey: Self.key) else {
            lastLoad = nil
            return .initial()
        }
        guard case let (state, outcome)? = Self.decode(data), !state.profiles.isEmpty else {
            backUp(data)
            lastLoad = .unreadable
            return .initial()
        }
        if outcome == .salvaged { backUp(data) }
        lastLoad = outcome == .salvaged ? .salvaged : .decoded
        return state
    }

    public func save(_ state: AppState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // A failed encode must not erase what's saved.
        guard let data = try? encoder.encode(state) else { return }
        backing.set(data, forKey: Self.key)
    }

    private static func decode(_ data: Data) -> (AppState, AppStateUpgrade.Outcome)? {
        try? AppStateUpgrade.decode(data)
    }

    private func backUp(_ data: Data) {
        guard backing.data(forKey: Self.backupKey) == nil else { return }
        backing.set(data, forKey: Self.backupKey)
    }
}

/// Stores per-profile, per-server credentials.
public protocol SecretStore: AnyObject, Sendable {
    func credential(profile: UUID, server: UUID) -> ServerCredential?
    func setCredential(_ credential: ServerCredential?, profile: UUID, server: UUID)
}

public extension SecretStore {
    static func account(profile: UUID, server: UUID) -> String {
        "\(profile.uuidString)|\(server.uuidString)"
    }

    /// Deletes a server's credentials for every listed profile.
    func removeCredentials(server: UUID, profiles: [UUID]) {
        for p in profiles { setCredential(nil, profile: p, server: server) }
    }

    /// Writes a login and reads it back, so a store that silently drops
    /// writes (a Keychain error) is reported instead of the form closing
    /// as if it had saved.
    func saveCredential(_ login: ServerCredential?, profile: UUID, server: UUID) throws {
        setCredential(login, profile: profile, server: server)
        guard let login else { return }
        guard credential(profile: profile, server: server) == login else {
            throw CredentialSaveError(status: (self as? KeychainStatusReporting)?.lastStatus)
        }
    }
}

/// A login that couldn't be stored on this Apple TV.
public struct CredentialSaveError: LocalizedError, Equatable, Sendable {
    /// The Keychain's `OSStatus`, when known.
    public var status: Int32?

    public init(status: Int32? = nil) { self.status = status }

    public var errorDescription: String? {
        let code = status.map { " (Keychain error \($0))" } ?? ""
        return "The login couldn't be saved on this Apple TV\(code). Try again, or restart the app."
    }
}

/// Stores that can say why their last write failed.
public protocol KeychainStatusReporting: AnyObject {
    var lastStatus: Int32? { get }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: ServerCredential] = [:]
    private let lock = NSLock()

    public init() {}

    public func credential(profile: UUID, server: UUID) -> ServerCredential? {
        lock.lock(); defer { lock.unlock() }
        return values[Self.account(profile: profile, server: server)]
    }

    public func setCredential(_ credential: ServerCredential?, profile: UUID, server: UUID) {
        lock.lock(); defer { lock.unlock() }
        values[Self.account(profile: profile, server: server)] = credential
    }
}

#if canImport(Security)
/// Keychain-backed credentials (generic passwords, JSON-encoded).
///
/// Writes update the existing item in place and only add one when there is
/// none, and every status is kept in `lastStatus` so callers can report a
/// failed save (see `SecretStore.saveCredential`).
///
/// Builds signed without a team (the simulator with "Sign to Run Locally",
/// or no paid Apple Developer membership) can be refused Keychain access
/// with `errSecMissingEntitlement`. Then logins go to `fallback` (a file in
/// the app's own container) so the app still works while developing; a
/// properly signed build never uses it.
public final class KeychainSecretStore: SecretStore, KeychainStatusReporting, @unchecked Sendable {
    let service: String
    let fallback: SecretStore?
    private let lock = NSLock()
    private var _lastStatus: Int32?
    public var lastStatus: Int32? { lock.withLock { _lastStatus } }

    public init(service: String = "com.rustedimac.MangaReader.credentials",
                fallback: SecretStore? = FileSecretStore.appDefault()) {
        self.service = service
        self.fallback = fallback
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func record(_ status: OSStatus) -> OSStatus {
        lock.withLock { _lastStatus = status }
        return status
    }

    public func credential(profile: UUID, server: UUID) -> ServerCredential? {
        var q = query(Self.account(profile: profile, server: server))
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let credential = try? JSONDecoder().decode(ServerCredential.self, from: data) {
            return credential
        }
        return fallback?.credential(profile: profile, server: server)
    }

    public func setCredential(_ credential: ServerCredential?, profile: UUID, server: UUID) {
        let account = Self.account(profile: profile, server: server)
        guard let credential, let data = try? JSONEncoder().encode(credential) else {
            _ = record(SecItemDelete(query(account) as CFDictionary))
            fallback?.setCredential(nil, profile: profile, server: server)
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = record(SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary))
        if status == errSecItemNotFound {
            var q = query(account)
            q.merge(attributes) { $1 }
            status = record(SecItemAdd(q as CFDictionary, nil))
        }
        if status == errSecSuccess {
            fallback?.setCredential(nil, profile: profile, server: server)
        } else if Self.usesFallback(status), let fallback {
            fallback.setCredential(credential, profile: profile, server: server)
            if fallback.credential(profile: profile, server: server) == credential { _ = record(errSecSuccess) }
        }
    }

    /// Statuses that mean this build can't use the Keychain at all.
    static func usesFallback(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }
}
#endif

/// Logins in a JSON file in the app's own container, excluded from
/// backups. Only `KeychainSecretStore` uses it, when the build can't use the
/// Keychain (see there).
public final class FileSecretStore: SecretStore, @unchecked Sendable {
    let url: URL
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    /// `Library/Application Support/credentials.json` in the app container.
    public static func appDefault() -> FileSecretStore? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return FileSecretStore(url: dir.appendingPathComponent("credentials.json"))
    }

    private func load() -> [String: ServerCredential] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: ServerCredential].self, from: data)) ?? [:]
    }

    public func credential(profile: UUID, server: UUID) -> ServerCredential? {
        lock.withLock { load()[Self.account(profile: profile, server: server)] }
    }

    public func setCredential(_ credential: ServerCredential?, profile: UUID, server: UUID) {
        lock.withLock {
            var all = load()
            let key = Self.account(profile: profile, server: server)
            guard all[key] != credential else { return }
            all[key] = credential
            if all.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return
            }
            guard let data = try? JSONEncoder().encode(all) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
            var target = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? target.setResourceValues(values)
        }
    }
}
