import Foundation

/// The add/edit server form's contents, kept separate from the UI so the
/// parsing and validation rules can be tested with `swift test`.
///
/// Fields are short on purpose: typing on an Apple TV is slow. For Kavita the
/// address field also accepts the full OPDS URL, which carries the API key.
///
/// A Kavita login is either a username and password (the app signs in and
/// keeps an auth key, never the password; see `KavitaClient.signIn`) or a
/// pasted API key / OPDS URL.
public struct ServerDraft: Equatable, Sendable {
    public enum KavitaSignInMethod: String, CaseIterable, Sendable, Identifiable {
        case password
        case apiKey

        public var id: String { rawValue }
        public var title: String { self == .password ? "Username & Password" : "API Key" }
    }

    public var kind: ServerKind
    public var name: String
    /// Server address, or (Kavita) a pasted OPDS URL.
    public var address: String
    public var apiKey: String
    public var username: String
    public var password: String
    public var syncProgress: Bool
    public var kavitaMethod: KavitaSignInMethod
    /// The profile's saved login when editing. An untouched form keeps it.
    public var existing: ServerCredential?

    public init(kind: ServerKind = .kavita, name: String = "", address: String = "", apiKey: String = "",
                username: String = "", password: String = "", syncProgress: Bool = true,
                kavitaMethod: KavitaSignInMethod = .apiKey, existing: ServerCredential? = nil) {
        self.kind = kind
        self.name = name
        self.address = address
        self.apiKey = apiKey
        self.username = username
        self.password = password
        self.syncProgress = syncProgress
        self.kavitaMethod = kavitaMethod
        self.existing = existing
    }

    /// A draft prefilled from a saved server and the active profile's login.
    /// A Kavita login made with a password shows the username and an empty
    /// password; leaving it that way keeps the saved login.
    public init(editing config: ServerConfig, credential: ServerCredential?, syncProgress: Bool) {
        let kavitaByPassword = config.kind == .kavita && (credential == nil || credential?.username != nil)
        self.init(kind: config.kind, name: config.name, address: config.baseURL.absoluteString,
                  apiKey: kavitaByPassword ? "" : credential?.apiKey ?? "", username: credential?.username ?? "",
                  password: config.kind == .kavita ? "" : credential?.password ?? "", syncProgress: syncProgress,
                  kavitaMethod: kavitaByPassword ? .password : .apiKey, existing: credential)
    }

    /// If `address` is a Kavita OPDS URL, splits it into the server address
    /// and API key fields and switches to API key sign-in. Returns true
    /// when it did.
    @discardableResult
    public mutating func absorbOPDS() -> Bool {
        guard kind == .kavita, let parsed = KavitaOPDS.parse(address) else { return false }
        address = parsed.baseURL.absoluteString
        apiKey = parsed.apiKey
        kavitaMethod = .apiKey
        return true
    }

    /// Kavita with a username and password, so the app has to sign in
    /// (`KavitaClient.signIn`) to get the credential.
    var usesKavitaPassword: Bool {
        kind == .kavita && kavitaMethod == .password && KavitaOPDS.parse(address) == nil
    }

    /// Editing a Kavita password login without typing a new password.
    public var keepsExistingLogin: Bool {
        guard usesKavitaPassword, password.isEmpty, let existing, existing.apiKey?.isEmpty == false else { return false }
        let typed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty || typed.caseInsensitiveCompare(existing.username ?? "") == .orderedSame
    }

    /// True when saving needs a Kavita sign-in with `username`/`password`.
    public var needsKavitaSignIn: Bool { usesKavitaPassword && !keepsExistingLogin }

    /// The server's base URL. Adds `http://` when no scheme was typed and
    /// drops a trailing slash. For Kavita, an OPDS URL resolves to its base.
    public var resolvedURL: URL? {
        if kind == .kavita, let parsed = KavitaOPDS.parse(address) { return parsed.baseURL }
        return Self.normalizedURL(address, keepQuery: kind == .opds)
    }

    public var resolvedAPIKey: String {
        if kind == .kavita, let parsed = KavitaOPDS.parse(address) { return parsed.apiKey }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why the form can't be saved yet, or nil when it can.
    public var validationMessage: String? {
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter the server address." }
        guard resolvedURL != nil else { return "That doesn't look like a web address." }
        if usesKavitaPassword {
            if keepsExistingLogin { return nil }
            if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter your Kavita username." }
            if password.isEmpty { return "Enter your Kavita password." }
            return nil
        }
        if kind == .kavita, resolvedAPIKey.isEmpty { return "Enter the API key, or paste the OPDS URL." }
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

    /// The login to save. Nil for a Kavita password login that still has
    /// to sign in (`needsKavitaSignIn`).
    public var credential: ServerCredential? {
        switch kind {
        case .kavita:
            if usesKavitaPassword { return keepsExistingLogin ? existing : nil }
            let key = resolvedAPIKey
            guard !key.isEmpty else { return nil }
            // Keep the known owner of an unchanged key.
            return ServerCredential(apiKey: key, username: existing?.apiKey == key ? existing?.username : nil)
        case .suwayomi:
            let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !user.isEmpty else { return nil }
            let unchanged = existing?.username == user && existing?.password == password
            return ServerCredential(username: user, password: password,
                                    suwayomiLogin: unchanged ? existing?.suwayomiLogin : nil)
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
