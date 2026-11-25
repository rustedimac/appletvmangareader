import SwiftUI
import MangaCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PlaceholderView(title: "Home", message: "Recently updated, newly added and continue reading rows will appear here.")
    }
}
