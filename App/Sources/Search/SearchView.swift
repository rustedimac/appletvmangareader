import SwiftUI
import MangaCore

struct SearchView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PlaceholderView(title: "Search", message: "Search across your servers.")
    }
}
