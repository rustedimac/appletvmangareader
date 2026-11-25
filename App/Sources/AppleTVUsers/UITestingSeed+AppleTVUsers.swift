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

    /// `-uiTestingOpenLink series:<server name>:<series id>` or
    /// `read:<server name>:<series id>:<chapter id>` opens that Top Shelf
    /// link at launch. Server ids are random in tests, so names are used.
    @MainActor
    static func openLink(in model: AppModel) -> DeepLink? {
        guard isUITesting, let spec = value(after: "-uiTestingOpenLink") else { return nil }
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count >= 3, let server = model.servers.first(where: { $0.name == parts[1] }) else { return nil }
        let ref = SeriesRef(serverID: server.id, seriesID: parts[2])
        switch parts[0] {
        case "series": return .series(ref, profile: model.activeProfile.id)
        case "read" where parts.count >= 4: return .read(ref, chapterID: parts[3], page: nil, profile: model.activeProfile.id)
        default: return nil
        }
    }
}
