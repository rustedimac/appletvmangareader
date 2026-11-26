import SwiftUI
import MangaCore

/// Top-level tabs. Each tab's folder under App/Sources is owned by one
/// workstream; replace the placeholder views there.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = UITestingSeed.initialTab ?? "home"
    /// A Top Shelf item the user opened.
    @State private var link: DeepLinkRoute?

    var body: some View {
        content
            .fullScreenCover(item: $link) { route in
                DeepLinkView(link: route.link)
            }
            .onOpenURL { url in
                if let parsed = DeepLink(url: url) { link = model.route(for: parsed) }
            }
            .task {
                TabBarScrollReset.install()
                model.startTopShelf()
                if let test = UITestingSeed.openLink(in: model) { link = model.route(for: test) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refreshStaleFavorites() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isPickingProfile {
            ProfilePickerView()
        } else {
            // Titles only, like Apple's own tvOS apps: with a symbol next to
            // every title the six tabs no longer fit the bar and it scrolls
            // sideways (Settings ends up cut off). TabBarLayoutUITests checks
            // that all six fit.
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Text("Home") }
                    .tag("home")
                LibraryView()
                    .tabItem { Text("Library") }
                    .tag("library")
                FavoritesView()
                    .tabItem { Text("Favorites") }
                    .tag("favorites")
                BookmarksView()
                    .tabItem { Text("Bookmarks") }
                    .tag("bookmarks")
                SearchView()
                    .tabItem { Text("Search") }
                    .tag("search")
                SettingsView()
                    .tabItem { Text("Settings") }
                    .tag("settings")
            }
            // Rebuild every tab for the newly picked profile.
            .id(model.activeProfile.id)
        }
    }
}

/// Shown by screens that have nothing to display yet.
struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Text(title).font(.title2)
            Text(message).foregroundStyle(.secondary)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
