import Foundation
import MangaCore

extension AppModel {
    /// Adds two offline demo servers ("Demo Kavita" and "Demo Suwayomi")
    /// backed by `SampleLibraryServer`. Used by UI tests launched with
    /// `-uiTesting -demoServers`, so browsing screens have content.
    /// With `-demoProgress`, every series starts with chapters 1 and 2 read
    /// and chapter 3 at page 6.
    func installDemoServers() {
        var demos: [UUID: SampleLibraryServer] = [:]
        let seedsProgress = ProcessInfo.processInfo.arguments.contains("-demoProgress")
        makeClient = { config, _, scope, _ in
            // Scoped copies of one instance per server share its progress.
            let base = demos[config.id] ?? {
                let server = SampleLibraryServer(config: config)
                if seedsProgress { server.seedProgress(read: 2, inProgressPage: 5) }
                return server
            }()
            demos[config.id] = base
            return base.scoped(to: scope)
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
        // `-demoFinished 1` marks Demo Kavita's series 1 fully read.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoFinished"), i + 1 < args.count,
           let server = servers.first(where: { $0.name == "Demo Kavita" }) {
            (client(for: server) as? SampleLibraryServer)?.markAllRead(seriesID: args[i + 1])
        }
    }
}
