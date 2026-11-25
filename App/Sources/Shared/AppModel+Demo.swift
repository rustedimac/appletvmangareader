import Foundation
import MangaCore

extension AppModel {
    /// Adds two offline demo servers ("Demo Kavita" and "Demo Suwayomi")
    /// backed by `SampleLibraryServer`. Used by UI tests launched with
    /// `-uiTesting -demoServers`, so browsing screens have content.
    func installDemoServers() {
        var demos: [UUID: SampleLibraryServer] = [:]
        makeClient = { config, _, _ in
            if let existing = demos[config.id] { return existing }
            let server = SampleLibraryServer(config: config)
            demos[config.id] = server
            return server
        }
        // Kavita sign-in accepts reader / secret.
        kavitaSignIn = { _, username, password, _ in
            guard username.lowercased() == "reader", password == "secret" else { throw MangaError.unauthorized }
            return ServerCredential(apiKey: "demo-key", username: "reader")
        }
        let base = URL(string: "https://demo.invalid")!
        for (kind, name) in [(ServerKind.kavita, "Demo Kavita"), (.suwayomi, "Demo Suwayomi")]
        where !servers.contains(where: { $0.name == name }) {
            saveServer(ServerConfig(kind: kind, name: name, baseURL: base), credential: nil)
        }
    }
}
