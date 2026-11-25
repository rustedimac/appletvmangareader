import SwiftUI
import MangaCore

extension AppModel {
    /// The active profile's favorites across every server, newest first,
    /// leaving out libraries/categories the profile doesn't import.
    var favorites: [Favorite] { state.visibleFavorites(profile: activeProfile.id) }
}

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                let favorites = model.favorites.map(\.series)
                if favorites.isEmpty {
                    BrowseMessage(title: "No favorites yet",
                                  message: "Open a series and choose Favorite to keep it here.",
                                  systemImage: "heart")
                } else {
                    SeriesGrid(series: favorites, showsServer: model.servers.count > 1)
                }
            }
            .seriesNavigation()
        }
    }
}
