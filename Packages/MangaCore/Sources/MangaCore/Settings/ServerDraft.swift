import Foundation

/// The add/edit server form's contents, kept separate from the UI so the
/// parsing and validation rules can be tested with `swift test`.
///
/// Fields are short on purpose: typing on an Apple TV is slow. For Kavita the
/// address field also accepts the full OPDS URL, which carries the API key.
public struct ServerDraft: Equatable, Sendable {
    public var kind: ServerKind
    public var name: String
    /// Server address, or (Kavita) a pasted OPDS URL.
    public var address: String
    public var apiKey: String
    public var username: String
    public var password: String
    public var syncProgress: Bool

    public init(kind: ServerKind = .kavita, name: String = "", address: String = "", apiKey: String = "",
                username: String = "", password: String = "", syncProgress: Bool = true) {
        self.kind = kind
        self.name = name
        self.address = address
        self.apiKey = apiKey
        self.username = username
        self.password = password
        self.syncProgress = syncProgress
    }

    /// A draft prefilled from a saved server and the active profile's login.
    public init(editing config: ServerConfig, credential: ServerCredential?, syncProgress: Bool) {
        self.init(kind: config.kind, name: config.name, address: config.baseURL.absoluteString,
                  apiKey: credential?.apiKey ?? "", username: credential?.username ?? "",
                  password: credential?.password ?? "", syncProgress: syncProgress)
    }

    /// Tidies the address (and, for Kavita, the API key) once the person is
    /// done typing: on Return, Test Connection or Save. Never call this on
    /// every keystroke: the address would rewrite itself mid-typing.
    ///
    /// For Kavita, a full OPDS URL in either field splits into the server
    /// address and the API key. Returns true when a field changed.
    @discardableResult
    public mutating func absorbOPDS() -> Bool {
        guard kind == .kavita else { return false }
        let before = (address, apiKey)
        if let parsed = KavitaOPDS.parse(address) {
            address = parsed.baseURL.absoluteString
            apiKey = parsed.apiKey
        } else if let url = resolvedURL, Self.trimmedServicePath(address, kind: kind) {
            // `http://host/api/opds/` with no key: keep just the server.
            address = url.absoluteString
        }
        let key = resolvedAPIKey
        if !key.isEmpty, key != apiKey { apiKey = key }
        return before != (address, apiKey)
    }

    /// The server's base URL. Adds `http://` when no scheme was typed and
    /// drops a trailing slash. For Kavita, an OPDS URL resolves to its base.
    /// The API path people often copy from the browser (`/api/opds/`,
    /// `/api/graphql`, `/api/v1`) is dropped for Kavita, Suwayomi and Komga.
    public var resolvedURL: URL? {
        if kind == .kavita, let parsed = KavitaOPDS.parse(address) { return parsed.baseURL }
        guard let url = Self.normalizedURL(address, keepQuery: kind == .opds) else { return nil }
        return Self.droppingServicePath(url, kind: kind)
    }

    /// The API key to use. For Kavita it comes from an OPDS URL in the
    /// address field, or from the API key field, which also accepts the
    /// whole OPDS URL (or just `api/opds/<key>`) pasted into it.
    public var resolvedAPIKey: String {
        if kind == .kavita, let parsed = KavitaOPDS.parse(address) { return parsed.apiKey }
        let typed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .kavita else { return typed }
        if let parsed = KavitaOPDS.parse(typed) { return parsed.apiKey }
        if let parsed = KavitaOPDS.parse("http://host/" + typed) { return parsed.apiKey }
        return typed
    }

    /// The help shown under the address field.
    public static func addressHelp(for kind: ServerKind) -> String {
        switch kind {
        case .kavita:
            return "Type the address you open Kavita at in a browser, for example http://kavita.local:5000. You can also use the full OPDS URL from Kavita → User Settings → 3rd Party Clients (it ends in /api/opds/ and your key); the API key is then filled in for you."
        case .komga:
            return "The address you open Komga at in a browser, for example http://komga.local:25600."
        case .suwayomi:
            return "The address you open Suwayomi at in a browser, for example http://suwayomi.local:4567."
        case .opds:
            return "The catalog URL, for example http://books.local:8083/opds. Just the address works for most servers."
        case .freeLibrary:
            return ""
        }
    }

    /// Path suffixes that point at a server's API rather than the server.
    static func servicePaths(for kind: ServerKind) -> [[String]] {
        switch kind {
        case .kavita: return [["api", "opds"], ["api"]]
        case .suwayomi: return [["api", "graphql"], ["api", "v1"], ["api"]]
        case .komga: return [["api", "v1"], ["api", "v2"], ["api"]]
        case .opds, .freeLibrary: return []
        }
    }

    static func droppingServicePath(_ url: URL, kind: ServerKind) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let parts = components.path.split(separator: "/").map { $0.lowercased() }
        for suffix in servicePaths(for: kind) where parts.count >= suffix.count && Array(parts.suffix(suffix.count)) == suffix {
            let kept = components.path.split(separator: "/").dropLast(suffix.count)
            components.path = kept.isEmpty ? "" : "/" + kept.joined(separator: "/")
            return components.url ?? url
        }
        return url
    }

    /// True when the typed address carries a path, slash or missing scheme
    /// that `resolvedURL` tidies away.
    static func trimmedServicePath(_ address: String, kind: ServerKind) -> Bool {
        guard let url = normalizedURL(address, keepQuery: kind == .opds) else { return false }
        return droppingServicePath(url, kind: kind) != url
    }

    /// Why the form can't be saved yet, or nil when it can.
    public var validationMessage: String? {
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter the server address." }
        guard resolvedURL != nil else { return "That doesn't look like a web address." }
        if kind == .kavita, resolvedAPIKey.isEmpty { return "Enter the API key from Kavita → User Settings → 3rd Party Clients, or use the full OPDS URL as the address." }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .suwayomi || kind == .opds, user.isEmpty != password.isEmpty { return "Enter both a username and a password, or neither." }
        if kind == .komga, resolvedAPIKey.isEmpty {
            if user.isEmpty && password.isEmpty { return "Enter an API key, or your Komga email and password." }
            if user.isEmpty || password.isEmpty { return "Enter both your Komga email and password." }
        }
        return nil
    }

    public var isValid: Bool { validationMessage == nil }

    /// The name to save: what was typed, or the server's host name.
    public var resolvedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return resolvedURL?.host ?? kind.displayName
    }

    public var credential: ServerCredential? {
        switch kind {
        case .kavita:
            let key = resolvedAPIKey
            return key.isEmpty ? nil : ServerCredential(apiKey: key)
        case .suwayomi:
            let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
            return user.isEmpty ? nil : ServerCredential(username: user, password: password)
        case .opds:
            let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
            return user.isEmpty ? nil : ServerCredential(username: user, password: password)
        case .komga:
            // An API key wins; the email and password are the fallback.
            let key = resolvedAPIKey
            if !key.isEmpty { return ServerCredential(apiKey: key) }
            let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
            return user.isEmpty ? nil : ServerCredential(username: user, password: password)
        case .freeLibrary:
            return nil
        }
    }

    /// The config to save. Pass the existing id when editing.
    public func config(id: UUID = UUID()) -> ServerConfig? {
        guard isValid, let url = resolvedURL else { return nil }
        return ServerConfig(id: id, kind: kind, name: resolvedName, baseURL: url)
    }

    /// Parses a typed address. Accepts `host`, `host:port`, or a full URL.
    /// OPDS catalog URLs keep their query (`keepQuery`).
    public static func normalizedURL(_ string: String, keepQuery: Bool = false) -> URL? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard var components = URLComponents(string: s),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        if !keepQuery { components.query = nil }
        components.fragment = nil
        return components.url
    }
}

public extension AppState {
    /// Profiles that write their reading progress to a server.
    func profilesSyncing(to server: UUID) -> [Profile] {
        profiles.filter { serverSettings(profile: $0.id, server: server).syncProgressToServer }
    }

    /// A name for a new profile that isn't taken yet: "Profile 2", "Profile 3"...
    func nextProfileName() -> String {
        let taken = Set(profiles.map { $0.name.lowercased() })
        var n = profiles.count + 1
        while taken.contains("profile \(n)") { n += 1 }
        return "Profile \(n)"
    }
}

/// Avatar choices for the profile editor (SF Symbol names). The app maps
/// `Profile.colorIndex` onto its own color palette.
public enum ProfileAvatars {
    public static let symbols: [String] = [
        "person.fill", "face.smiling", "star.fill", "heart.fill", "bolt.fill", "flame.fill",
        "leaf.fill", "moon.fill", "sun.max.fill", "cloud.fill", "pawprint.fill", "hare.fill",
        "tortoise.fill", "bird.fill", "fish.fill", "gamecontroller.fill", "book.fill", "crown.fill",
    ]
    public static let colorCount = 8
}
