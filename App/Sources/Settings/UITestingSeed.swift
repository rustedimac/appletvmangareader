import Foundation
import MangaCore

/// Launch arguments that set up state for XCUITests (only read with
/// `-uiTesting`, which also makes all storage in-memory).
///
/// - `-uiTestingSeed profiles`: two profiles, so the picker shows at launch.
/// - `-uiTestingSeed servers`: one profile with a Kavita and a Suwayomi server.
/// - `-uiTestingSeed multiAddress`: a Kavita server with a home and a remote address.
/// - `-uiTestingTab settings`: start on the Settings tab.
/// - `-uiTestingNavigationResetDelay 2`: tabs return to their top screen
///   after 2 s out of sight instead of 10 (`NavigationReset`).
/// - `-homePerServer`: Home rows per server instead of merged (the default).
/// - `-posterServerLabel onCover|off`: where posters name their server.
/// - `-serverEditorPrefill <kind>|<address>[|<api key>]`: Add Server opens
///   with these fields filled in, as if pasted (the tvOS simulator can't
///   paste from the Mac). Works in Debug builds even without `-uiTesting`,
///   e.g. `-serverEditorPrefill "kavita|http://kavita.local:5000/api/opds/fake-key"`.
/// - `-welcome`: let the first-run welcome show (it never does in UI tests
///   otherwise). Without `-freeLibrary` it starts from an empty install with
///   the offline Free Library client ready for "Start Reading".
enum UITestingSeed {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static var isUITesting: Bool { arguments.contains("-uiTesting") }

    static var initialTab: String? { isUITesting ? value(after: "-uiTestingTab") : nil }

    static var navigationResetDelay: Duration? {
        guard isUITesting, let raw = value(after: "-uiTestingNavigationResetDelay"),
              let seconds = Double(raw) else { return nil }
        return .seconds(seconds)
    }

    struct ServerPrefill {
        var kind: ServerKind
        var address: String
        var apiKey: String
    }

    static var serverEditorPrefill: ServerPrefill? {
        #if !DEBUG
        guard isUITesting else { return nil }
        #endif
        guard let raw = value(after: "-serverEditorPrefill") else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let kind = ServerKind(rawValue: parts[0]) else { return nil }
        return ServerPrefill(kind: kind, address: parts[1], apiKey: parts.count > 2 ? parts[2] : "")
    }

    static func state() -> AppState? {
        guard isUITesting, let seed = value(after: "-uiTestingSeed") else { return nil }
        var s = AppState.initial()
        switch seed {
        case "profiles":
            s.addProfile(name: "Kid", symbol: "star.fill", colorIndex: 3)
        case "servers":
            s.addServer(ServerConfig(kind: .kavita, name: "Test Kavita", baseURL: URL(string: "http://kavita.test")!))
            s.addServer(ServerConfig(kind: .suwayomi, name: "Test Suwayomi", baseURL: URL(string: "http://suwayomi.test")!))
        case "multiAddress":
            s.addServer(ServerConfig(kind: .kavita, name: "Home Kavita", baseURL: URL(string: "http://kavita.test")!,
                                     alternateURLs: [URL(string: "https://kavita-remote.test")!]))
        default:
            return nil
        }
        applyAppleTVUserSeed(&s)
        return s
    }
}

extension AppModel {
    /// `-uiTesting -liveServers`: adds real servers from environment
    /// variables, so live checks need no typing on the simulator keyboard
    /// and no secret ever lands in the repo.
    ///
    /// - `MR_KAVITA_OPDS`: a Kavita OPDS URL (`http://host/api/opds/<key>`).
    /// - `MR_SUWAYOMI_URL`: a Suwayomi base URL.
    /// - `MR_SUWAYOMI_USER` / `MR_SUWAYOMI_PASS`: optional basic auth.
    func installLiveServersFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let opds = env["MR_KAVITA_OPDS"], let parsed = KavitaOPDS.parse(opds) {
            try? saveServer(ServerConfig(kind: .kavita, name: "Kavita", baseURL: parsed.baseURL),
                       credential: ServerCredential(apiKey: parsed.apiKey))
        }
        if let raw = env["MR_SUWAYOMI_URL"], let url = URL(string: raw) {
            let user = env["MR_SUWAYOMI_USER"]
            let credential = user.map { ServerCredential(username: $0, password: env["MR_SUWAYOMI_PASS"]) }
            try? saveServer(ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: url), credential: credential)
        }
    }
}

extension AppModel {
    /// `-homePerServer` and `-posterServerLabel <value>` (see `UITestingSeed`).
    func applyUITestingHomeLayout() {
        let perServer = UITestingSeed.arguments.contains("-homePerServer")
        let label = UITestingSeed.value(after: "-posterServerLabel").flatMap(PosterServerLabel.init(rawValue:))
        guard perServer || label != nil else { return }
        // Every profile, so seeds with a profile picker get it too.
        update { state in
            for profile in state.profiles.map(\.id) {
                state.updateBrowse(profile: profile) { prefs in
                    if perServer { prefs.home.serverRows = .perServer }
                    if let label { prefs.home.serverLabel = label }
                }
            }
        }
    }
}
