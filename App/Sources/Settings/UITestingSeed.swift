import Foundation
import MangaCore

/// Launch arguments that set up state for XCUITests (only read with
/// `-uiTesting`, which also makes all storage in-memory).
///
/// - `-uiTestingSeed profiles`: two profiles, so the picker shows at launch.
/// - `-uiTestingSeed servers`: one profile with a Kavita and a Suwayomi server.
/// - `-uiTestingSeed pins`: "Me" with PIN 1111 that's asked for on open, and
///   "Kid" with PIN 3333 (not asked on open) and Horror hidden.
/// - `-uiTestingSeed filtered`: one profile with the Horror genre hidden
///   (use with `-demoServers`; Horror is every fifth demo series).
/// - `-uiTestingTab settings`: start on the Settings tab.
enum UITestingSeed {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static var isUITesting: Bool { arguments.contains("-uiTesting") }

    static var initialTab: String? { isUITesting ? value(after: "-uiTestingTab") : nil }

    static func state() -> AppState? {
        guard isUITesting, let seed = value(after: "-uiTestingSeed") else { return nil }
        var s = AppState.initial()
        switch seed {
        case "profiles":
            s.addProfile(name: "Kid", symbol: "star.fill", colorIndex: 3)
        case "servers":
            s.addServer(ServerConfig(kind: .kavita, name: "Test Kavita", baseURL: URL(string: "http://kavita.test")!))
            s.addServer(ServerConfig(kind: .suwayomi, name: "Test Suwayomi", baseURL: URL(string: "http://suwayomi.test")!))
        case "pins":
            let kid = s.addProfile(name: "Kid", symbol: "star.fill", colorIndex: 3)
            s.setContentFilter(ContentFilter(hiddenGenres: ["Horror"]), profile: kid.id)
            if let me = s.profiles.first { s.setRequiresPINToOpen(true, profile: me.id) }
        case "filtered":
            if let me = s.profiles.first { s.setContentFilter(ContentFilter(hiddenGenres: ["Horror"]), profile: me.id) }
        default:
            return nil
        }
        return s
    }

    /// PINs for the "pins" seed. Only the hashes go in the store.
    static func seedPINs(_ state: AppState, into pins: PINStore) {
        guard isUITesting, value(after: "-uiTestingSeed") == "pins" else { return }
        for profile in state.profiles {
            switch profile.name {
            case "Me": pins.setPIN("1111", profile: profile.id)
            case "Kid": pins.setPIN("3333", profile: profile.id)
            default: break
            }
        }
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
            saveServer(ServerConfig(kind: .kavita, name: "Kavita", baseURL: parsed.baseURL),
                       credential: ServerCredential(apiKey: parsed.apiKey))
        }
        if let raw = env["MR_SUWAYOMI_URL"], let url = URL(string: raw) {
            let user = env["MR_SUWAYOMI_USER"]
            let credential = user.map { ServerCredential(username: $0, password: env["MR_SUWAYOMI_PASS"]) }
            saveServer(ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: url), credential: credential)
        }
    }
}
