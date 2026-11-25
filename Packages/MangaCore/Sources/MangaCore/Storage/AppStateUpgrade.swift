import Foundation

/// Loads saved `AppState` JSON written by any earlier build, so an app
/// update never resets profiles, favorites or reading progress.
///
/// Three layers, tried in order:
/// 1. `migrate` rewrites older JSON shapes to the current one, step by step
///    from the saved `version` (see `AppStateUpgrade.step(from:)`).
/// 2. The normal `Codable` decode. Models give new fields defaults
///    (`decodeIfPresent`), so this handles almost every upgrade.
/// 3. `salvage`: if the normal decode still fails, decode piece by piece and
///    keep everything that can be read. One bad entry costs that entry, not
///    the whole state.
///
/// When you change the shape of anything `AppState` stores, add the JSON a
/// build *before* your change writes to `AppStateUpgradeTests` (the
/// `Fixtures` list) so every past shape stays covered.
public enum AppStateUpgrade {
    public enum Outcome: Equatable, Sendable {
        /// Decoded normally (after any migrations).
        case decoded
        /// Decoded only partly; some entries couldn't be read and were left
        /// out. The original bytes are kept under `StateStore.backupKey`.
        case salvaged
    }

    public enum UpgradeError: Error {
        case notJSON
    }

    /// Decodes saved state of any past version.
    public static func decode(_ data: Data) throws -> (AppState, Outcome) {
        let migrated = try migrate(data)
        if let state = try? JSONDecoder().decode(AppState.self, from: migrated) {
            return (state, .decoded)
        }
        let salvaged = try JSONDecoder().decode(SalvagedAppState.self, from: migrated).state
        return (salvaged, .salvaged)
    }

    /// Runs every migration step from the saved version up to
    /// `AppState.currentVersion`. Data that needs none is returned as is.
    /// State saved by a newer build (a downgrade) is left alone: its extra
    /// fields are ignored by the decoder.
    public static func migrate(_ data: Data) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpgradeError.notJSON
        }
        let saved = (json["version"] as? Int) ?? 1
        guard saved < AppState.currentVersion || json["version"] == nil else { return data }
        for version in saved..<max(saved, AppState.currentVersion) {
            step(from: version)(&json)
        }
        json["version"] = AppState.currentVersion
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// The change from `version` to `version + 1`. When you bump
    /// `AppState.currentVersion`, add a case here that rewrites the old
    /// shape (rename keys, move data) rather than dropping it.
    static func step(from version: Int) -> (inout [String: Any]) -> Void {
        switch version {
        default:
            return { _ in }
        }
    }
}

// MARK: Salvage

/// Decodes a value, or nil if it can't be read. Never throws.
struct Lossy<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where Key == AnyKey {
    func lossy<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        (try? decodeIfPresent(Lossy<T>.self, forKey: AnyKey(key)))?.value
    }

    func lossyArray<T: Decodable>(_ type: T.Type, _ key: String) -> [T] {
        (try? decodeIfPresent([Lossy<T>].self, forKey: AnyKey(key)))?.compactMap(\.value) ?? []
    }

    func lossyDictionary<T: Decodable>(_ type: T.Type, _ key: String) -> [String: T] {
        let raw = (try? decodeIfPresent([String: Lossy<T>].self, forKey: AnyKey(key))) ?? [:]
        return raw.compactMapValues(\.value)
    }
}

/// `AppState` read piece by piece, keeping whatever can be decoded.
struct SalvagedAppState: Decodable {
    var state: AppState

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var state = AppState()
        state.version = AppState.currentVersion
        state.profiles = c.lossyArray(Profile.self, "profiles")
        state.activeProfileID = c.lossy(UUID.self, "activeProfileID")
        state.servers = c.lossyArray(ServerConfig.self, "servers")
        state.profileData = c.lossyDictionary(SalvagedProfileData.self, "profileData").mapValues(\.data)
        // Progress is worth more than a profile's name: if the profile list
        // was unreadable, bring back a profile for each set of data.
        let known = Set(state.profiles.map(\.id.uuidString))
        for key in state.profileData.keys.sorted() where !known.contains(key) {
            guard let id = UUID(uuidString: key) else { continue }
            state.profiles.append(Profile(id: id, name: "Profile \(state.profiles.count + 1)",
                                          colorIndex: state.profiles.count))
        }
        self.state = state
    }
}

/// `ProfileData` read normally, or piece by piece if that fails.
struct SalvagedProfileData: Decodable {
    var data: ProfileData

    init(from decoder: Decoder) throws {
        if let whole = try? ProfileData(from: decoder) {
            data = whole
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        var d = ProfileData()
        d.serverSettings = c.lossyDictionary(ProfileServerSettings.self, "serverSettings")
        d.favorites = c.lossyArray(Favorite.self, "favorites")
        d.progress = c.lossyDictionary(SeriesProgress.self, "progress")
        d.defaultReaderSettings = c.lossy(ReaderSettings.self, "defaultReaderSettings") ?? .default
        d.readerOverrides = c.lossyDictionary(ReaderSettings.self, "readerOverrides")
        d.bookmarks = c.lossyArray(Bookmark.self, "bookmarks")
        d.favoritesSort = c.lossy(FavoritesSort.self, "favoritesSort") ?? .default
        d.webtoonAutoScrollLevel = c.lossy(Int.self, "webtoonAutoScrollLevel")
        let recent = c.lossyDictionary(SeriesSummary.self, "recentSeries")
        d.recentSeries = recent.isEmpty ? nil : recent
        data = d
    }
}
