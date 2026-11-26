import SwiftUI
import MangaCore

extension AppModel {
    /// The active profile's favorites across every server, newest first,
    /// leaving out libraries/categories the profile doesn't import and
    /// anything its content filter hides.
    var favorites: [Favorite] { state.visibleFavorites(profile: activeProfile.id, hidden: hiddenSeries) }
}

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                if model.favorites.isEmpty {
                    BrowseMessage(title: "No favorites yet",
                                  message: "Open a series and choose Favorite to keep it here.",
                                  systemImage: "heart")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        FavoritesSortBar()
                        FavoritesGrid()
                    }
                }
            }
            .seriesNavigation()
            .task(id: model.contentKey) { await model.refreshStaleFavorites() }
            .themedScreen()
        }
        .task(id: model.contentFilter.cacheKey) { await model.refreshHiddenSeries() }
        .resetsNavigationWhenLeft()
    }
}

/// The favorites in the profile's order. Its own view, so the sort it
/// depends on is read here and not only by `FavoritesView`, whose body can
/// re-run during the press that changes the sort.
private struct FavoritesGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sort = model.favoritesSort
        let favorites = model.sortedFavorites.map(\.series)
        SeriesGrid(series: favorites, showsServer: model.servers.count > 1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("favorites.grid")
            .accessibilityValue(favorites.map(\.ref.seriesID).joined(separator: ","))
            // Rebuild on a new order: LazyVGrid can keep stale cell
            // positions when every item moves at once (a reversal).
            .id(sort)
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
                        changeSort { $0.selecting(key) }
                    }
                    .accessibilityIdentifier("favorites.sort.\(key.rawValue)")
                }
                Button {
                    changeSort { $0.reversed() }
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

    /// Writes the new sort after the press's own update pass. Written during
    /// it, SwiftUI sometimes dropped the change for the grid, which then kept
    /// the old order (about half the time in UI tests). Reads the current
    /// sort at that point, so quick presses build on each other.
    private func changeSort(_ change: @escaping (FavoritesSort) -> FavoritesSort) {
        let model = self.model
        Task { @MainActor in model.setFavoritesSort(change(model.favoritesSort)) }
    }
}
