import SwiftUI
import MangaCore

@main
struct MangaReaderApp: App {
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel
    @State private var cloudSync: CloudSyncController

    init() {
        let model = AppModel.live()
        let cloudSync = CloudSyncController(model: model)
        model.onStateChange = { [weak cloudSync] in cloudSync?.stateDidChange() }
        SyncAppDelegate.controller = cloudSync
        _model = State(initialValue: model)
        _cloudSync = State(initialValue: cloudSync)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ReaderDemo.isEnabled {
                    ReaderDemo.RootView()
                } else {
                    RootView()
                }
            }
            .environment(model)
            .environment(cloudSync)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { cloudSync.syncNow() }
        }
    }
}
