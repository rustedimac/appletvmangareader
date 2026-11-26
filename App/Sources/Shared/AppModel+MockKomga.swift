import Foundation
import MangaCore

extension AppModel {
    /// Adds "Test Komga", signed in with the mock's API key, whose requests
    /// go to `MockKomgaTransport` instead of the network. Used by UI tests
    /// launched with `-uiTesting -mockKomga`, so the real `KomgaClient`
    /// runs end to end. Other servers are unaffected.
    func installMockKomga() {
        let mock = MockKomgaTransport()
        let previous = makeClient
        makeClient = { config, credential, scope, transport in
            guard config.kind == .komga else { return previous(config, credential, scope, transport) }
            return previous(config, credential, scope, mock)
        }
        guard !servers.contains(where: { $0.name == "Test Komga" }) else { return }
        try? saveServer(ServerConfig(kind: .komga, name: "Test Komga", baseURL: URL(string: "http://komga.test")!),
                   credential: ServerCredential(apiKey: MockKomgaTransport.apiKey))
    }
}
