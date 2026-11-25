import Foundation
import MangaCore

/// UI test launch arguments for Apple TV users.
///
/// - `-appleTVUserMode`: behave as if running as the current Apple TV user.
/// - `-uiTestingRememberProfile <name>`: that profile was picked last by this
///   Apple TV user (use with `-uiTestingSeed profiles`).
/// - `-uiTestingSharedServers`: another Apple TV user already added
///   "Family Kavita" to the shared directory.
extension UITestingSeed {
    static var perAppleTVUser: Bool { isUITesting && arguments.contains("-appleTVUserMode") }

    static func applyAppleTVUserSeed(_ s: inout AppState) {
        if let name = value(after: "-uiTestingRememberProfile"),
           let profile = s.profiles.first(where: { $0.name == name }) {
            s.pickProfile(profile.id, remember: true)
        }
    }

    static func sharedServers() -> SharedServerDirectory? {
        guard isUITesting, arguments.contains("-uiTestingSharedServers") else { return nil }
        let server = ServerConfig(kind: .kavita, name: "Family Kavita", baseURL: URL(string: "http://kavita.test")!)
        return SharedServerDirectory(servers: [server],
                                     credentials: [server.id.uuidString: ServerCredential(apiKey: "shared-test-key")])
    }
}
