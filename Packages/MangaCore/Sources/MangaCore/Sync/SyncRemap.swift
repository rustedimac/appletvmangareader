import Foundation

/// Local ids to replace with the ids another device already uses for the
/// same thing. When a device joins sync (or restores a backup) it usually
/// has its own "Me" profile and may have added the same Kavita server
/// itself; without this they'd show up twice.
///
/// Servers match by kind and address, profiles by name (ignoring case).
public struct SyncRemap: Sendable, Equatable {
    /// local id → incoming id
    public var servers: [UUID: UUID] = [:]
    public var profiles: [UUID: UUID] = [:]

    public init(servers: [UUID: UUID] = [:], profiles: [UUID: UUID] = [:]) {
        self.servers = servers
        self.profiles = profiles
    }

    public var isEmpty: Bool { servers.isEmpty && profiles.isEmpty }

    /// Matches local servers and profiles that aren't in `incoming` to
    /// incoming ones that look the same.
    public static func matching(incoming: [SyncRecord], local state: AppState) -> SyncRemap {
        var remap = SyncRemap()
        let live = incoming.filter { !$0.isDeleted }

        let remoteServers = live.filter { $0.kind == .server }.compactMap { r -> ServerConfig? in
            guard var s = r.payload.flatMap({ SyncMapper.decode(ServerConfig.self, $0) }),
                  let id = UUID(uuidString: r.id) else { return nil }
            s.id = id
            return s
        }
        let localServerIDs = Set(state.servers.map(\.id))
        var taken = Set<UUID>()
        for local in state.servers where !remoteServers.contains(where: { $0.id == local.id }) {
            if let match = remoteServers.first(where: {
                !localServerIDs.contains($0.id) && !taken.contains($0.id)
                    && $0.kind == local.kind && sameAddress($0.baseURL, local.baseURL)
            }) {
                remap.servers[local.id] = match.id
                taken.insert(match.id)
            }
        }

        let remoteProfiles = live.filter { $0.kind == .profile }.compactMap { r -> Profile? in
            guard var p = r.payload.flatMap({ SyncMapper.decode(Profile.self, $0) }),
                  let id = UUID(uuidString: r.id) else { return nil }
            p.id = id
            return p
        }
        let localProfileIDs = Set(state.profiles.map(\.id))
        taken = []
        for local in state.profiles where !remoteProfiles.contains(where: { $0.id == local.id }) {
            if let match = remoteProfiles.first(where: {
                !localProfileIDs.contains($0.id) && !taken.contains($0.id) && sameName($0.name, local.name)
            }) {
                remap.profiles[local.id] = match.id
                taken.insert(match.id)
            }
        }
        return remap
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    /// Same scheme, host (any case), port and path (ignoring a trailing slash).
    static func sameAddress(_ a: URL, _ b: URL) -> Bool {
        func norm(_ u: URL) -> String {
            var c = URLComponents(url: u, resolvingAgainstBaseURL: false) ?? URLComponents()
            c.scheme = c.scheme?.lowercased()
            c.host = c.host?.lowercased()
            if c.port == 80 && c.scheme == "http" || c.port == 443 && c.scheme == "https" { c.port = nil }
            while c.path.hasSuffix("/") { c.path.removeLast() }
            c.query = nil
            c.fragment = nil
            return c.string ?? u.absoluteString
        }
        return norm(a) == norm(b)
    }

    func server(_ id: UUID) -> UUID { servers[id] ?? id }
    func profile(_ id: UUID) -> UUID { profiles[id] ?? id }

    /// Keychain logins to move, computed from the state before the remap.
    func credentialMoves(in state: AppState) -> [SyncApplyEffects.CredentialMove] {
        var moves: [SyncApplyEffects.CredentialMove] = []
        for p in state.profiles {
            for s in state.servers where profile(p.id) != p.id || server(s.id) != s.id {
                moves.append(.init(fromProfile: p.id, fromServer: s.id, toProfile: profile(p.id), toServer: server(s.id)))
            }
        }
        return moves
    }

    /// Rewrites every id in the state. Data under the old id is merged into
    /// what's already under the new one (newest progress wins).
    func apply(to state: inout AppState) {
        for i in state.servers.indices { state.servers[i].id = server(state.servers[i].id) }
        for i in state.profiles.indices { state.profiles[i].id = profile(state.profiles[i].id) }
        state.activeProfileID = state.activeProfileID.map(profile)

        func key(_ storageKey: String) -> String {
            guard let bar = storageKey.firstIndex(of: "|"),
                  let s = UUID(uuidString: String(storageKey[..<bar])) else { return storageKey }
            return server(s).uuidString + String(storageKey[bar...])
        }

        var newData: [String: ProfileData] = [:]
        for (pid, d) in state.profileData {
            var d = d
            d.serverSettings = Dictionary(d.serverSettings.map { (k, v) in
                (UUID(uuidString: k).map { server($0).uuidString } ?? k, v)
            }, uniquingKeysWith: { a, _ in a })
            for i in d.favorites.indices {
                d.favorites[i].series.ref.serverID = server(d.favorites[i].series.ref.serverID)
            }
            d.progress = Dictionary(d.progress.map { (key($0.key), $0.value) },
                                    uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
            d.readerOverrides = Dictionary(d.readerOverrides.map { (key($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
            if var b = d.browse {
                b.libraries = Dictionary(b.libraries.map { (key($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
                b.dismissedContinueReading = Dictionary(b.dismissedContinueReading.map { (key($0.key), $0.value) },
                                                        uniquingKeysWith: { max($0, $1) })
                for i in b.caughtUp.indices {
                    b.caughtUp[i].series.ref.serverID = server(b.caughtUp[i].series.ref.serverID)
                }
                d.browse = b
            }

            let newID = UUID(uuidString: pid).map { profile($0).uuidString } ?? pid
            if var existing = newData[newID] {
                existing.serverSettings.merge(d.serverSettings) { a, _ in a }
                for f in d.favorites where !existing.favorites.contains(where: { $0.series.ref == f.series.ref }) {
                    existing.favorites.append(f)
                }
                existing.progress.merge(d.progress) { $0.updatedAt >= $1.updatedAt ? $0 : $1 }
                existing.readerOverrides.merge(d.readerOverrides) { a, _ in a }
                if existing.browse == nil { existing.browse = d.browse }
                newData[newID] = existing
            } else {
                newData[newID] = d
            }
        }
        state.profileData = newData
    }
}
