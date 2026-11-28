import Foundation
import MangaCore

#if DEBUG
/// Debug builds only: adds servers handed to the app at launch, so a set of
/// test servers can be put on a simulator without typing them in
/// (`tools/test-servers/README.md`):
///
///     SIMCTL_CHILD_MR_ADD_SERVERS='[{"kind":"calibre","name":"Test Calibre","url":"http://localhost:8080",
///       "username":"tester","password":"…"}]' xcrun simctl launch <device> com.rustedimac.MangaReader
///
/// `kind` is a `ServerKind` raw value; `apiKey`, `username` and `password`
/// are optional. A server already saved with the same type and address is
/// updated in place. The login is saved for the active profile, like the
/// server editor does. Nothing here is compiled into release builds.
extension AppModel {
    struct LaunchServer: Decodable {
        var kind: ServerKind
        var name: String
        var url: URL
        var apiKey: String?
        var username: String?
        var password: String?
    }

    func addServersFromLaunchEnvironment() {
        guard let raw = ProcessInfo.processInfo.environment["MR_ADD_SERVERS"],
              let list = try? JSONDecoder().decode([LaunchServer].self, from: Data(raw.utf8)) else { return }
        for item in list where ServerKind.userAddable.contains(item.kind) {
            let existing = state.servers.first { $0.kind == item.kind && $0.baseURL == item.url }
            let config = ServerConfig(id: existing?.id ?? UUID(), kind: item.kind, name: item.name, baseURL: item.url,
                                      alternateURLs: existing?.alternateURLs ?? [])
            let hasLogin = [item.apiKey, item.username].contains { !($0 ?? "").isEmpty }
            let credential = hasLogin
                ? ServerCredential(apiKey: item.apiKey, username: item.username, password: item.password)
                : nil
            try? saveServer(config, credential: credential)
        }
    }
}
#endif
