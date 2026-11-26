import Foundation
import XCTest

/// Helpers for the upgrade-safety tests: walk saved JSON by key path, drop
/// or change one field everywhere it appears, and compare what survives.
///
/// Paths name object keys joined by dots. Array elements are `[]` and
/// dictionary keys that are ids (UUIDs, `SeriesRef.storageKey`, sync record
/// keys) are `*`, so `profileData.*.favorites[].series.title` is the title
/// of every favorite of every profile.
enum SavedJSON {
    static func load(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                          subdirectory: "Fixtures/SavedData") else {
            throw NSError(domain: "SavedJSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func parse(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func data(_ json: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .fragmentsAllowed])
    }

    /// Whether a dictionary key is data (an id) rather than a field name.
    static func isDynamicKey(_ key: String) -> Bool {
        key.contains("|") || key.contains("/") || UUID(uuidString: key) != nil
    }

    private static func child(_ path: String, _ key: String) -> String {
        let part = isDynamicKey(key) ? "*" : key
        return path.isEmpty ? part : "\(path).\(part)"
    }

    /// Every field path in `json` (objects' named keys only).
    static func fieldPaths(_ json: Any) -> Set<String> {
        var out = Set<String>()
        func walk(_ value: Any, _ path: String) {
            if let object = value as? [String: Any] {
                for (key, v) in object {
                    let p = child(path, key)
                    if !isDynamicKey(key) { out.insert(p) }
                    walk(v, p)
                }
            } else if let array = value as? [Any] {
                for v in array { walk(v, path + "[]") }
            }
        }
        walk(json, "")
        return out
    }

    /// Paths whose values are strings, with every value seen there.
    static func stringLeaves(_ json: Any) -> [String: [String]] {
        var out: [String: [String]] = [:]
        func walk(_ value: Any, _ path: String) {
            if let object = value as? [String: Any] {
                for (key, v) in object { walk(v, child(path, key)) }
            } else if let array = value as? [Any] {
                for v in array { walk(v, path + "[]") }
            } else if let string = value as? String {
                out[path, default: []].append(string)
            }
        }
        walk(json, "")
        return out
    }

    /// `json` with the field at `path` removed everywhere.
    static func removing(_ path: String, from json: Any) -> Any {
        transform(json, "", target: path) { _ in nil }
    }

    /// `json` with every value at `path` replaced.
    static func replacing(_ path: String, in json: Any, with body: @escaping (Any) -> Any) -> Any {
        transform(json, "", target: path) { body($0) }
    }

    private static func transform(_ value: Any, _ path: String, target: String, _ body: (Any) -> Any?) -> Any {
        if var object = value as? [String: Any] {
            for (key, v) in object {
                let p = child(path, key)
                if p == target {
                    object[key] = body(v)
                } else if target.hasPrefix(p) {
                    object[key] = transform(v, p, target: target, body)
                }
            }
            return object
        }
        if let array = value as? [Any] {
            let p = path + "[]"
            if p == target { return array.compactMap(body) }
            return array.map { transform($0, p, target: target, body) }
        }
        return value
    }

    /// How many elements every array and dictionary holds, by path. The
    /// measure of "nothing was lost".
    static func counts(_ json: Any) -> [String: Int] {
        var out: [String: Int] = [:]
        func walk(_ value: Any, _ path: String) {
            if let object = value as? [String: Any] {
                if object.keys.contains(where: isDynamicKey) { out[path, default: 0] += object.count }
                for (key, v) in object { walk(v, child(path, key)) }
            } else if let array = value as? [Any] {
                out[path, default: 0] += array.count
                for v in array { walk(v, path + "[]") }
            }
        }
        walk(json, "")
        return out
    }

    /// The same JSON with arrays of plain values sorted (`Set`s encode in
    /// any order) and re-serialized, so two trees compare as `Data`.
    static func canonical(_ json: Any) throws -> Data {
        func normalize(_ value: Any) -> Any {
            if let object = value as? [String: Any] { return object.mapValues(normalize) }
            if let array = value as? [Any] {
                let mapped = array.map(normalize)
                if let strings = mapped as? [String] { return strings.sorted() }
                return mapped
            }
            return value
        }
        return try data(normalize(json))
    }

    /// Collections that shrank (or vanished) between `before` and `after`,
    /// ignoring paths at or under `ignoring`.
    static func losses(before: Any, after: Any, ignoring: String? = nil) -> [String] {
        let a = counts(before), b = counts(after)
        return a.compactMap { path, n in
            if let ignoring, path == ignoring || path.hasPrefix(ignoring + ".") || path.hasPrefix(ignoring + "[]") {
                return nil
            }
            let m = b[path] ?? 0
            return m < n ? "\(path): \(n) -> \(m)" : nil
        }.sorted()
    }
}

/// Walks a decoded value with `Mirror` and reports the MangaCore fields
/// (as `Type.field`) that are never set anywhere in it: nil, or an empty
/// collection. Run on the newest fixture, it names fields added since that
/// fixture was made.
enum FieldPresence {
    static func unsetFields(in value: Any) -> Set<String> {
        var seen = Set<String>()
        var set = Set<String>()
        func isOurs(_ value: Any) -> Bool {
            String(reflecting: type(of: value)).hasPrefix("MangaCore.")
        }
        func walk(_ value: Any, _ path: String) {
            let mirror = Mirror(reflecting: value)
            switch mirror.displayStyle {
            case .optional:
                if let wrapped = mirror.children.first?.value { walk(wrapped, path) }
            case .collection, .set:
                for element in mirror.children { walk(element.value, path + "[]") }
            case .dictionary:
                for pair in mirror.children {
                    if let v = Mirror(reflecting: pair.value).children.dropFirst().first?.value { walk(v, path + ".*") }
                }
            case .struct where isOurs(value):
                let typeName = String(describing: type(of: value))
                for field in mirror.children {
                    guard let label = field.label else { continue }
                    let name = "\(typeName).\(label)"
                    seen.insert(name)
                    if isPresent(field.value) { set.insert(name) }
                    walk(field.value, name)
                }
            default:
                break
            }
        }
        walk(value, "")
        return seen.subtracting(set)
    }

    private static func isPresent(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            guard let wrapped = mirror.children.first?.value else { return false }
            return isPresent(wrapped)
        case .collection, .set, .dictionary:
            return !mirror.children.isEmpty
        default:
            return true
        }
    }
}
