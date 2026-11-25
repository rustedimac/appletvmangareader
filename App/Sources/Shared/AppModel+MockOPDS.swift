import Foundation
import MangaCore

extension AppModel {
    /// Adds "Test OPDS", whose requests go to `MockOPDSTransport` instead
    /// of the network, so the real `OPDSClient` runs end to end. Used by UI
    /// tests launched with `-uiTesting -mockOPDS`.
    func installMockOPDS() {
        let mock = MockOPDSTransport()
        let previous = makeClient
        makeClient = { config, credential, scope, transport in
            guard config.kind == .opds else { return previous(config, credential, scope, transport) }
            return previous(config, credential, scope, mock)
        }
        guard !servers.contains(where: { $0.name == "Test OPDS" }) else { return }
        let server = ServerConfig(kind: .opds, name: "Test OPDS", baseURL: URL(string: "http://opds.test")!)
        saveServer(server, credential: nil)
        setServerSettings(ProfileServerSettings(syncProgressToServer: false), for: server)
    }
}
