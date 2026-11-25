import Foundation
import MangaCore

/// Launch arguments that set up state for XCUITests (only read with
/// `-uiTesting`, which also makes all storage in-memory).
///
/// - `-uiTestingSeed profiles`: two profiles, so the picker shows at launch.
/// - `-uiTestingSeed servers`: one profile with a Kavita and a Suwayomi server.
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
        default:
            return nil
        }
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
