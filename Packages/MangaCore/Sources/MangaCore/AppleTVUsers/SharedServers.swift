import Foundation
#if canImport(Security)
import Security
#endif

/// The servers every Apple TV user of this app shares.
///
/// When the app runs as the current Apple TV user, each user gets their own
/// app data (profiles, favorites, progress). Servers are kept here as well,
/// in the user-independent keychain, so a server added by one person shows
/// up for everyone without adding it again. Removed servers are remembered
/// so the removal reaches the other users too.
public struct SharedServerDirectory: Codable, Hashable, Sendable {
    public var servers: [ServerConfig]
    /// Servers someone removed. Other users drop them on their next launch.
    public var removedServerIDs: Set<UUID>
    /// The login whoever added the server used, keyed by server id. Other
    /// users fall back to it until they enter their own.
    public var credentials: [String: ServerCredential]

    public init(servers: [ServerConfig] = [], removedServerIDs: Set<UUID> = [],
                credentials: [String: ServerCredential] = [:]) {
        self.servers = servers
        self.removedServerIDs = removedServerIDs
        self.credentials = credentials
    }

    public func credential(for server: UUID) -> ServerCredential? { credentials[server.uuidString] }

    /// Records this user's server list after a change: servers that were in
    /// `before` but not `after` are removed for everyone; everything in
    /// `after` is added or updated.
    public mutating func record(before: [ServerConfig], after: [ServerConfig]) {
        let afterIDs = Set(after.map(\.id))
        for gone in before where !afterIDs.contains(gone.id) && gone.kind != .freeLibrary {
            servers.removeAll { $0.id == gone.id }
            credentials[gone.id.uuidString] = nil
            removedServerIDs.insert(gone.id)
        }
        upsert(after)
    }

    /// Adds or updates servers without removing any. The built-in Free
    /// Library isn't shared: every user has it unless they remove it.
    public mutating func upsert(_ list: [ServerConfig]) {
        for server in list where !removedServerIDs.contains(server.id) && server.kind != .freeLibrary {
            if let i = servers.firstIndex(where: { $0.id == server.id }) {
                servers[i] = server
            } else {
                servers.append(server)
            }
        }
    }

    /// Keeps the first login seen for a server.
    public mutating func offerCredential(_ credential: ServerCredential?, for server: UUID) {
        guard let credential, credentials[server.uuidString] == nil,
              servers.contains(where: { $0.id == server }) else { return }
        credentials[server.uuidString] = credential
    }
}

public extension AppState {
    /// Brings this user's servers in line with the shared directory: adds
    /// servers other users added, applies renames and address changes, and
    /// drops servers someone removed. Returns the ids of removed servers so
    /// the caller can delete their logins.
    ///
    /// Servers adopted from another user don't sync reading progress for
    /// any profile here (they'd be using that user's login, and on Suwayomi
    /// its single progress). Each profile can turn sync on after entering
    /// its own login.
    @discardableResult
    mutating func adopt(_ directory: SharedServerDirectory) -> [UUID] {
        var removed: [UUID] = []
        for id in directory.removedServerIDs where server(id) != nil {
            removeServer(id)
            removed.append(id)
        }
        for shared in directory.servers {
            if let local = server(shared.id) {
                if local != shared { updateServer(shared) }
            } else {
                servers.append(shared)
                for profile in profiles {
                    setServerSettings(ProfileServerSettings(syncProgressToServer: false), profile: profile.id,
                                      server: shared.id)
                }
            }
        }
        return removed
    }
}

/// Where the shared server directory is kept.
public protocol SharedServerStore: AnyObject, Sendable {
    func load() -> SharedServerDirectory?
    func save(_ directory: SharedServerDirectory)
}

public final class InMemorySharedServerStore: SharedServerStore, @unchecked Sendable {
    private var value: SharedServerDirectory?
    private let lock = NSLock()

    public init(_ value: SharedServerDirectory? = nil) { self.value = value }

    public func load() -> SharedServerDirectory? { lock.withLock { value } }
    public func save(_ directory: SharedServerDirectory) { lock.withLock { value = directory } }
}

#if canImport(Security)
/// Keeps the directory in one keychain item. On tvOS it goes in the
/// user-independent keychain (`kSecUseUserIndependentKeychain`), which every
/// Apple TV user of the app can read. That needs the
/// `com.apple.developer.user-management` entitlement with
/// `runs-as-current-user-with-user-independent-keychain`; elsewhere it's an
/// ordinary keychain item.
public final class KeychainSharedServerStore: SharedServerStore, @unchecked Sendable {
    let service: String
    let account = "servers"
    private let lock = NSLock()
    private var cached: SharedServerDirectory??

    public init(service: String = "com.rustedimac.MangaReader.shared") {
        self.service = service
    }

    private func query() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        #if os(tvOS)
        q[kSecUseUserIndependentKeychain as String] = true
        #endif
        return q
    }

    public func load() -> SharedServerDirectory? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        var value: SharedServerDirectory?
        if SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            value = try? JSONDecoder().decode(SharedServerDirectory.self, from: data)
        }
        cached = .some(value)
        return value
    }

    public func save(_ directory: SharedServerDirectory) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(directory) else { return }
        cached = .some(directory)
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query() as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var q = query()
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
#endif

/// A profile's own logins, falling back to the shared login for servers
/// another Apple TV user added. Writing a login also offers it as the
/// shared one when the server has none yet.
public final class SharedFallbackSecretStore: SecretStore, KeychainStatusReporting, @unchecked Sendable {
    public let local: SecretStore
    public let shared: SharedServerStore

    public var lastStatus: Int32? { (local as? KeychainStatusReporting)?.lastStatus }

    public init(local: SecretStore, shared: SharedServerStore) {
        self.local = local
        self.shared = shared
    }

    public func credential(profile: UUID, server: UUID) -> ServerCredential? {
        local.credential(profile: profile, server: server) ?? shared.load()?.credential(for: server)
    }

    /// True when the profile has its own login rather than the shared one.
    public func hasOwnCredential(profile: UUID, server: UUID) -> Bool {
        local.credential(profile: profile, server: server) != nil
    }

    public func setCredential(_ credential: ServerCredential?, profile: UUID, server: UUID) {
        local.setCredential(credential, profile: profile, server: server)
        guard let credential, var directory = shared.load(),
              directory.credential(for: server) == nil,
              directory.servers.contains(where: { $0.id == server }) else { return }
        directory.offerCredential(credential, for: server)
        shared.save(directory)
    }
}
