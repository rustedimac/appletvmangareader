import Foundation
import MangaCore

extension AppModel {
    /// Adds the built-in Free Library on launch unless the user removed it.
    func installFreeLibraryIfNeeded() {
        guard state.freeLibraryRemoved != true, !state.hasFreeLibrary else { return }
        update { $0.installFreeLibraryIfNeeded() }
    }

    /// "Add the Free Library" in Settings, after it was removed.
    func restoreFreeLibrary() {
        update { $0.restoreFreeLibrary() }
    }

    /// UI tests (`-uiTesting -freeLibrary`): the Free Library with the
    /// bundled catalog and canned manifests and episodes
    /// (`FreeLibraryDemoTransport`), so nothing depends on archive.org or
    /// peppercarrot.com being up. Page images still load from the network
    /// when it's there; tests don't depend on them.
    func installFreeLibraryDemo() {
        useFreeLibraryDemoTransport()
        installFreeLibraryIfNeeded()
    }

    /// The offline Free Library client without adding the library, for
    /// `-welcome` tests that start from an empty install and add it from
    /// the welcome.
    func useFreeLibraryDemoTransport() {
        let store = FreeLibraryStore(remoteURL: nil, cacheFile: nil)
        let transport = FreeLibraryDemoTransport()
        let previous = makeClient
        makeClient = { config, credential, scope, http in
            config.kind == .freeLibrary
                ? FreeLibraryClient(config: config, categoryScope: scope, transport: transport, store: store)
                : previous(config, credential, scope, http)
        }
    }
}
