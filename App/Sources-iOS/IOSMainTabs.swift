import SwiftUI

/// The iPhone and iPad tabs (docs/IOS.md §2): a bottom tab bar on iPhone and
/// in compact iPad windows, a top tab bar that turns into a sidebar on iPad.
/// Search uses the search role so it sits apart from the other tabs.
///
/// Unlike tvOS, tabs keep their screens while out of sight (iOS convention),
/// so none of them opt in to `NavigationReset`.
///
/// The iPhone tab bar holds four tabs plus Search before it folds the rest
/// into "More", so in compact width Bookmarks leaves the bar (it stays in the
/// iPad bar and sidebar, and each series page lists its own bookmarks).
/// TODO(PR 3): a Bookmarks entry in Favorites for compact width.
///
/// iPad sidebar: a Servers section under the tabs opens each server's
/// library directly (sidebar only; the tab bar keeps the six tabs).
struct IOSMainTabs: View {
    @Binding var tab: String
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: "home") {
                HomeView()
            }
            .accessibilityIdentifier("tab.home")
            Tab("Library", systemImage: "books.vertical", value: "library") {
                LibraryView()
            }
            .accessibilityIdentifier("tab.library")
            Tab("Favorites", systemImage: "heart", value: "favorites") {
                FavoritesView()
            }
            .accessibilityIdentifier("tab.favorites")
            if sizeClass != .compact {
                Tab("Bookmarks", systemImage: "bookmark", value: "bookmarks") {
                    BookmarksView()
                }
                .accessibilityIdentifier("tab.bookmarks")
            }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
            .accessibilityIdentifier("tab.settings")
            Tab("Search", systemImage: "magnifyingglass", value: "search", role: .search) {
                SearchView()
            }
            .accessibilityIdentifier("tab.search")
            if sizeClass != .compact, !model.servers.isEmpty {
                TabSection("Servers") {
                    ForEach(model.servers) { server in
                        Tab(server.name, systemImage: server.kind.symbolName, value: "server.\(server.id)") {
                            NavigationStack {
                                ServerLibraryView(server: server)
                                    .seriesNavigation()
                            }
                        }
                        .accessibilityIdentifier("tab.server.\(server.id)")
                    }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
