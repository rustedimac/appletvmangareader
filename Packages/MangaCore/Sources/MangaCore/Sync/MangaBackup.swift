import Foundation

/// A versioned JSON backup of everything that syncs: works with no Apple
/// Developer membership and no iCloud, and is a readable file an iPhone or
/// Mac version could import.
///
/// ```json
/// {
///   "format": "mangareader-backup",
///   "version": 1,
///   "exportedAt": "2026-11-25T10:00:00Z",
///   "app": "0.1.0",
///   "records": [
///     { "key": "favorite/<profile>/<server>|42", "kind": "favorite",
///       "modifiedAt": "2026-11-20T08:00:00Z", "value": { ... } }
///   ]
/// }
/// ```
///
/// Same records and merge rules as iCloud sync. Restoring merges: favorites
/// and servers are added, progress keeps the furthest-along position and
/// every read chapter, and settings take the backup's values. Nothing is
/// deleted. Logins and API keys are never in a backup.
public enum MangaBackup {
    public static let format = "mangareader-backup"
    public static let version = 1

    public enum BackupError: Error, Equatable, LocalizedError {
        case notABackup
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .notABackup: return "This file isn't a Manga Reader backup."
            case .newerVersion(let v): return "This backup was made by a newer version of the app (format \(v)). Update the app first."
            }
        }
    }

    // MARK: Export

    public static func export(state: AppState, appVersion: String? = nil, deviceID: String = "backup",
                              now: Date = Date()) -> Data {
        let records = SyncMerge.localRecords(state: state, reference: [:], deviceID: deviceID, now: now, joining: true)
            .values.sorted { $0.key < $1.key }
        let iso = ISO8601DateFormatter()
        let items: [[String: Any]] = records.compactMap { r in
            guard let payload = r.payload,
                  let value = try? JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed]) else { return nil }
            // Values without their own date are stamped with the export time,
            // so restoring brings back the settings in the backup.
            let stamp = r.modifiedAt == .distantPast ? now : r.modifiedAt
            return ["key": r.key, "kind": r.kind.rawValue, "modifiedAt": iso.string(from: stamp), "value": value]
        }
        var root: [String: Any] = ["format": format, "version": version, "exportedAt": iso.string(from: now), "records": items]
        if let appVersion { root["app"] = appVersion }
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: Import

    public static func parse(_ data: Data) throws -> [SyncRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == format,
              let v = root["version"] as? Int,
              let items = root["records"] as? [[String: Any]] else { throw BackupError.notABackup }
        guard v <= version else { throw BackupError.newerVersion(v) }
        let iso = ISO8601DateFormatter()
        return items.compactMap { item in
            guard let key = item["key"] as? String, let kind = item["kind"] as? String,
                  key.hasPrefix(kind + "/"),
                  let value = item["value"],
                  let payload = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            else { return nil }
            let date = (item["modifiedAt"] as? String).flatMap(iso.date(from:)) ?? .distantPast
            return SyncRecord(key: key, kind: SyncKind(kind), payload: payload, modifiedAt: date, deviceID: "backup")
        }
    }

    /// The changes that restoring `backup` makes to `state`.
    public static func restorePatch(state: AppState, backup: [SyncRecord], deviceID: String = "local") -> SyncPatch {
        let incoming = backup.filter { !$0.isDeleted && SyncMapper.canRead($0) }
        let remap = SyncRemap.matching(incoming: incoming, local: state)
        var remapped = state
        if !remap.isEmpty { remap.apply(to: &remapped) }
        let local = SyncMerge.localRecords(state: remapped, reference: [:], deviceID: deviceID,
                                           now: Date(), joining: true)
        var records: [SyncRecord] = []
        for b in incoming {
            guard let l = local[b.key] else { records.append(b); continue }
            let merged: SyncRecord
            if b.kind == .progress {
                merged = SyncMerge.merge(l, b)
            } else {
                merged = l.modifiedAt > b.modifiedAt ? l : b
            }
            if !SyncMapper.samePayload(b.kind, merged.payload, l.payload) { records.append(merged) }
        }
        return SyncPatch(remap: remap, records: records)
    }

    /// A short summary for the person, e.g. "3 favorites, 12 series' progress".
    public static func summary(_ effects: SyncApplyEffects) -> String {
        let names: [(SyncKind, String, String)] = [
            (.server, "server", "servers"), (.profile, "profile", "profiles"),
            (.favorite, "favorite", "favorites"), (.progress, "series' progress", "series' progress"),
            (.readerDefaults, "reader default", "reader defaults"),
            (.readerOverride, "series reader setting", "series reader settings"),
            (.serverSettings, "server setting", "server settings"),
        ]
        let parts = names.compactMap { kind, one, many -> String? in
            guard let n = effects.appliedCount[kind], n > 0 else { return nil }
            return "\(n) \(n == 1 ? one : many)"
        }
        return parts.isEmpty ? "Nothing new: everything in the backup was already here." : parts.joined(separator: ", ")
    }
}
