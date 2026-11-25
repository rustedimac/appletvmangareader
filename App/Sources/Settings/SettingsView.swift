import SwiftUI
import MangaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PlaceholderView(title: "Settings", message: "Manage profiles and servers.")
    }
}
