import SwiftUI
import MangaCore

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PlaceholderView(title: "Favorites", message: "Series you favorite will appear here.")
    }
}
