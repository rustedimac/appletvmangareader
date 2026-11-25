import SwiftUI
import MangaCore

extension AppModel {
    /// The active profile's favorites across every server, newest first.
    var favorites: [Favorite] { state.favorites(profile: activeProfile.id) }
}

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                let favorites = model.sortedFavorites.map(\.series)
                if favorites.isEmpty {
                    BrowseMessage(title: "No favorites yet",
                                  message: "Open a series and choose Favorite to keep it here.",
                                  systemImage: "heart")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        FavoritesSortBar()
                        SeriesGrid(series: favorites, showsServer: model.servers.count > 1)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("favorites.grid")
                            // Rebuild on a new order: LazyVGrid can keep stale cell
                            // positions when every item moves at once (a reversal).
                            .id(model.favoritesSort)
                    }
                }
            }
            .seriesNavigation()
            .task { await model.refreshStaleFavorites() }
        }
    }
}

/// Sort options above the Favorites grid. Picking the current option again
/// flips the direction, and so does the direction button. The choice is
/// saved for the profile.
struct FavoritesSortBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sort = model.favoritesSort
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                Text("Sort")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(FavoritesSortKey.allCases) { key in
                    OptionButton(title: key.title, isSelected: sort.key == key) {
                        model.setFavoritesSort(sort.selecting(key))
                    }
                    .accessibilityIdentifier("favorites.sort.\(key.rawValue)")
                }
                Button {
                    model.setFavoritesSort(sort.reversed())
                } label: {
                    Label(sort.directionLabel, systemImage: sort.ascending ? "arrow.up" : "arrow.down")
                        .font(.callout)
                }
                .accessibilityIdentifier("favorites.sort.direction")
                .accessibilityValue(sort.ascending ? "ascending" : "descending")
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }
}
