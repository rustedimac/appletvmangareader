import Foundation

/// Turns `AppState` into `SyncRecord`s and applies records back.
///
/// What syncs (see docs/ICLOUD.md):
/// - servers (name, kind, address; never logins or API keys),
/// - profiles (name, symbol, color),
/// - per profile: per-server settings (library selection, progress sync
///   toggle), favorites, reading progress, default reader settings and
///   per-series reader settings, and browse preferences (Home rows, poster
///   size, per-library sort and reading style).
///
/// Secrets stay in the device's Keychain. New features add a `Domain` to
/// `domains` with their own kind; nothing else in sync has to change.
public enum SyncMapper {
    /// A kind of record: how to read it from state and write it back.
    struct Domain {
        let kind: SyncKind
        /// Apply order: servers and profiles before what refers to them.
        let order: Int
        /// id → canonical payload, for everything of this kind in the state.
        let values: (AppState) -> [String: Data]
        /// Whether two payloads mean the same value.
        let same: (Data, Data) -> Bool
        /// Whether this build can read the payload.
        let readable: (Data) -> Bool
        /// A timestamp the value carries itself, used for records this device
        /// never synced before (so a device joining sync doesn't stamp
        /// everything "now" and overwrite the cloud).
        let natural: (Data) -> Date?
        /// Writes the value (nil = delete). Returns side effects.
        let apply: (inout AppState, String, Data?, inout SyncApplyEffects) -> Void
    }

    // MARK: Encoding

    static func encode<V: Encodable>(_ value: V) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(value)) ?? Data()
    }

    static func decode<V: Decodable>(_ type: V.Type, _ data: Data) -> V? {
        try? JSONDecoder().decode(type, from: data)
    }

    static func domain<V: Codable & Equatable>(
        _ kind: SyncKind, order: Int, _ type: V.Type,
        natural: @escaping (V) -> Date? = { _ in nil },
        values: @escaping (AppState) -> [String: V],
        apply: @escaping (inout AppState, String, V?, inout SyncApplyEffects) -> Void
    ) -> Domain {
        Domain(kind: kind, order: order,
               values: { values($0).mapValues { encode($0) } },
               same: { a, b in a == b || (decode(V.self, a).map { $0 == decode(V.self, b) } ?? false) },
               readable: { decode(V.self, $0) != nil },
               natural: { decode(V.self, $0).flatMap(natural) },
               apply: { state, id, data, effects in
                   if let data {
                       guard let value = decode(V.self, data) else { return }
                       apply(&state, id, value, &effects)
                   } else {
                       apply(&state, id, nil, &effects)
                   }
               })
    }

    // MARK: Payloads that need a canonical form

    /// `ProfileServerSettings` with the selection as a sorted list, so the
    /// same selection always encodes the same way.
    struct SyncedServerSettings: Codable, Equatable {
        var syncProgressToServer: Bool
        var selectedCategoryIDs: [String]?

        init(_ s: ProfileServerSettings) {
            syncProgressToServer = s.syncProgressToServer
            selectedCategoryIDs = s.selectedCategoryIDs.map { $0.sorted() }
        }

        func apply(to s: inout ProfileServerSettings) {
            s.syncProgressToServer = syncProgressToServer
            s.selectedCategoryIDs = selectedCategoryIDs.map(Set.init)
        }
    }

    // MARK: Ids

    /// "<profile>/<rest>" → (profile, rest).
    static func split(_ id: String) -> (UUID, String)? {
        guard let slash = id.firstIndex(of: "/"), let profile = UUID(uuidString: String(id[..<slash])) else { return nil }
        return (profile, String(id[id.index(after: slash)...]))
    }

    static func perProfile<V>(_ state: AppState, _ body: (ProfileData) -> [String: V]) -> [String: V] {
        var out: [String: V] = [:]
        for (profile, data) in state.profileData {
            for (id, v) in body(data) { out["\(profile)/\(id)"] = v }
        }
        return out
    }

    static func data(_ state: inout AppState, _ profile: UUID, _ body: (inout ProfileData) -> Void) {
        var d = state.profileData[profile.uuidString] ?? ProfileData()
        body(&d)
        state.profileData[profile.uuidString] = d
    }

    // MARK: Domains

    static let domains: [Domain] = [
        domain(.server, order: 0, ServerConfig.self,
               values: { Dictionary($0.servers.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a }) },
               apply: { state, id, value, effects in
                   guard let uuid = UUID(uuidString: id) else { return }
                   if var value {
                       value.id = uuid
                       if state.server(uuid) != nil { state.updateServer(value) } else { state.addServer(value) }
                   } else if state.server(uuid) != nil {
                       state.removeServer(uuid)
                       effects.removedServerIDs.insert(uuid)
                   }
               }),
        domain(.profile, order: 1, Profile.self,
               values: { Dictionary($0.profiles.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a }) },
               apply: { state, id, value, effects in
                   guard let uuid = UUID(uuidString: id) else { return }
                   if var value {
                       value.id = uuid
                       if state.profiles.contains(where: { $0.id == uuid }) {
                           state.updateProfile(value)
                       } else {
                           state.profiles.append(value)
                           if state.profileData[id] == nil { state.profileData[id] = ProfileData() }
                       }
                   } else if state.removeProfile(uuid) {
                       effects.removedProfileIDs.insert(uuid)
                   }
               }),
        domain(.serverSettings, order: 2, SyncedServerSettings.self,
               values: { perProfile($0) { $0.serverSettings.mapValues(SyncedServerSettings.init) } },
               apply: { state, id, value, _ in
                   guard let (profile, server) = split(id) else { return }
                   data(&state, profile) { d in
                       if let value {
                           var s = d.serverSettings[server] ?? ProfileServerSettings()
                           value.apply(to: &s)
                           d.serverSettings[server] = s
                       } else {
                           d.serverSettings[server] = nil
                       }
                   }
               }),
        domain(.favorite, order: 3, Favorite.self, natural: { $0.addedAt },
               values: { perProfile($0) { d in
                   Dictionary(d.favorites.map { ($0.series.ref.storageKey, $0) }, uniquingKeysWith: { a, _ in a })
               } },
               apply: { state, id, value, _ in
                   guard let (profile, key) = split(id) else { return }
                   data(&state, profile) { d in
                       d.favorites.removeAll { $0.series.ref.storageKey == key }
                       if let value { d.favorites.append(value) }
                   }
               }),
        domain(.progress, order: 4, SyncedProgress.self, natural: { $0.positionAt },
               values: { perProfile($0) { d in
                   d.progress.mapValues { p in
                       var marks: [String: ReadMark] = [:]
                       for c in p.unreadChapterIDs { marks[c] = ReadMark(read: false, at: p.updatedAt) }
                       for c in p.readChapterIDs { marks[c] = ReadMark(read: true, at: p.updatedAt) }
                       return SyncedProgress(chapterID: p.chapterID, page: p.page, positionAt: p.updatedAt, marks: marks,
                                             ignoresServerProgress: p.ignoresServerProgress ? true : nil)
                   }
               } },
               apply: { state, id, value, _ in
                   guard let (profile, key) = split(id) else { return }
                   data(&state, profile) { d in
                       guard let value else { d.progress[key] = nil; return }
                       // Keep fields this device stores beside the position.
                       var p = d.progress[key] ?? SeriesProgress(chapterID: value.chapterID, page: value.page,
                                                                  updatedAt: value.positionAt)
                       p.chapterID = value.chapterID
                       p.page = value.page
                       p.updatedAt = value.positionAt
                       p.readChapterIDs = value.readChapterIDs
                       // Every unread mark means "marked unread somewhere";
                       // keep it so the server's read state doesn't win.
                       p.unreadChapterIDs = value.unreadChapterIDs
                       p.ignoresServerProgress = value.ignoresServerProgress ?? false
                       d.progress[key] = p
                   }
               }),
        domain(.readerDefaults, order: 5, ReaderSettings.self,
               values: { state in
                   Dictionary(uniqueKeysWithValues: state.profileData.map { ($0.key, $0.value.defaultReaderSettings) })
               },
               apply: { state, id, value, _ in
                   guard let profile = UUID(uuidString: id) else { return }
                   data(&state, profile) { $0.defaultReaderSettings = value ?? .default }
               }),
        domain(.readerOverride, order: 6, ReaderSettings.self,
               values: { perProfile($0) { $0.readerOverrides } },
               apply: { state, id, value, _ in
                   guard let (profile, key) = split(id) else { return }
                   data(&state, profile) { $0.readerOverrides[key] = value }
               }),
        domain(.browse, order: 7, BrowsePreferences.self,
               values: { state in
                   state.profileData.compactMapValues { $0.browse }
               },
               apply: { state, id, value, _ in
                   guard let profile = UUID(uuidString: id) else { return }
                   data(&state, profile) { $0.browse = value }
               }),
    ]

    static let byKind: [SyncKind: Domain] = Dictionary(uniqueKeysWithValues: domains.map { ($0.kind, $0) })

    public static var knownKinds: Set<SyncKind> { Set(byKind.keys) }

    // MARK: Public API

    /// key → (kind, payload) for everything in the state that syncs.
    public static func payloads(from state: AppState) -> [String: (kind: SyncKind, payload: Data)] {
        var out: [String: (kind: SyncKind, payload: Data)] = [:]
        for d in domains {
            for (id, payload) in d.values(state) { out[SyncRecord.key(d.kind, id)] = (d.kind, payload) }
        }
        return out
    }

    /// Whether two payloads (nil = deleted) mean the same thing.
    public static func samePayload(_ kind: SyncKind, _ a: Data?, _ b: Data?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return byKind[kind]?.same(a, b) ?? (a == b)
        default: return false
        }
    }

    /// Whether this build understands the record. Records it doesn't are
    /// kept in the cloud untouched.
    public static func canRead(_ record: SyncRecord) -> Bool {
        guard let d = byKind[record.kind] else { return false }
        return record.payload.map(d.readable) ?? true
    }

    static func naturalDate(_ kind: SyncKind, _ payload: Data) -> Date? {
        byKind[kind]?.natural(payload)
    }

    /// Applies remapped ids, then records, in dependency order.
    @discardableResult
    public static func apply(_ patch: SyncPatch, to state: inout AppState) -> SyncApplyEffects {
        var effects = SyncApplyEffects()
        if !patch.remap.isEmpty {
            effects.credentialMoves = patch.remap.credentialMoves(in: state)
            patch.remap.apply(to: &state)
        }
        let sorted = patch.records.compactMap { r in byKind[r.kind].map { (r, $0) } }
            .sorted { $0.1.order < $1.1.order }
        for (record, domain) in sorted {
            domain.apply(&state, record.id, record.payload, &effects)
            effects.appliedCount[record.kind, default: 0] += 1
        }
        return effects
    }
}

/// Changes to make to local state: first id remaps, then records.
public struct SyncPatch: Sendable {
    public var remap: SyncRemap
    public var records: [SyncRecord]

    public init(remap: SyncRemap = SyncRemap(), records: [SyncRecord] = []) {
        self.remap = remap
        self.records = records
    }

    public var isEmpty: Bool { remap.isEmpty && records.isEmpty }
}

/// What applying a patch did that the app must follow up on outside
/// `AppState`: Keychain logins to move or delete.
public struct SyncApplyEffects: Sendable, Equatable {
    public struct CredentialMove: Sendable, Equatable {
        public var fromProfile: UUID, fromServer: UUID, toProfile: UUID, toServer: UUID
    }

    public var credentialMoves: [CredentialMove] = []
    public var removedServerIDs: Set<UUID> = []
    public var removedProfileIDs: Set<UUID> = []
    public var appliedCount: [SyncKind: Int] = [:]

    public init() {}

    public var totalApplied: Int { appliedCount.values.reduce(0, +) }

    /// Moves and deletes Keychain logins to match.
    public func applyCredentials(to secrets: SecretStore, servers: [UUID], profiles: [UUID]) {
        for m in credentialMoves {
            guard let c = secrets.credential(profile: m.fromProfile, server: m.fromServer) else { continue }
            secrets.setCredential(nil, profile: m.fromProfile, server: m.fromServer)
            if secrets.credential(profile: m.toProfile, server: m.toServer) == nil {
                secrets.setCredential(c, profile: m.toProfile, server: m.toServer)
            }
        }
        for s in removedServerIDs { secrets.removeCredentials(server: s, profiles: profiles + Array(removedProfileIDs)) }
        for p in removedProfileIDs {
            for s in servers + Array(removedServerIDs) { secrets.setCredential(nil, profile: p, server: s) }
        }
    }
}
