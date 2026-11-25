import SwiftUI
import MangaCore

@main
struct MangaReaderApp: App {
    @State private var model = AppModel.live()

    init() {
        AudioSessionSetup.configure()
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
        }
    }
}
