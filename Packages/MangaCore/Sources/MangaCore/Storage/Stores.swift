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

/// Loads and saves `AppState` as JSON.
public final class StateStore: @unchecked Sendable {
    public static let key = "mangareader.appstate.v1"
    let backing: KeyValueStore

    public init(backing: KeyValueStore) {
        self.backing = backing
    }

    public func load() -> AppState {
        guard let data = backing.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(AppState.self, from: data),
              !state.profiles.isEmpty else {
            return .initial()
        }
        return state
    }

    public func save(_ state: AppState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        backing.set(try? encoder.encode(state), forKey: Self.key)
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
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    let service: String

    public init(service: String = "com.rustedimac.MangaReader.credentials") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func credential(profile: UUID, server: UUID) -> ServerCredential? {
        var q = query(Self.account(profile: profile, server: server))
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ServerCredential.self, from: data)
    }

    public func setCredential(_ credential: ServerCredential?, profile: UUID, server: UUID) {
        let account = Self.account(profile: profile, server: server)
        SecItemDelete(query(account) as CFDictionary)
        guard let credential, let data = try? JSONEncoder().encode(credential) else { return }
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
#endif
