import Foundation

/// Decoding helpers for saved data. Saved data outlives the build that
/// wrote it, so a field that's missing (saved before it existed) or holds a
/// value this build doesn't know (an enum case from a newer build) falls
/// back to a default instead of failing the value that holds it. Use these
/// in every `init(from:)` of a type the app saves (see
/// docs/UPGRADE_SAFETY.md; `SavedDataUpgradeTests` checks every field).
extension KeyedDecodingContainer {
    /// The value, or `fallback` when it's missing or can't be read.
    func tolerant<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }

    /// The value, or nil when it's missing or can't be read.
    func tolerant<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// The elements that can be read; unreadable ones are skipped.
    func tolerantArray<T: Decodable>(_ key: Key) -> [T] {
        ((try? decodeIfPresent([Lossy<T>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
    }

    /// The entries that can be read; unreadable ones are skipped.
    func tolerantDictionary<T: Decodable>(_ key: Key) -> [String: T] {
        ((try? decodeIfPresent([String: Lossy<T>].self, forKey: key)) ?? nil)?.compactMapValues(\.value) ?? [:]
    }
}
