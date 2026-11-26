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
    /// Sends a tab back to its top screen after it's been out of sight.
    @State private var navigationReset = NavigationReset()

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
                if phase == .active {
                    Task { await model.refreshStaleFavorites() }
                    Task { await model.retryPendingProgressNow() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isPickingProfile {
            ProfilePickerView()
        } else if model.showsWelcome || model.isBusyInWelcome {
            // Nothing to read yet: pick Free Library collections, add a
            // server or restore a backup (see `Welcome`).
            WelcomeView()
                .id(model.activeProfile.id)
        } else {
            // Titles only, like Apple's own tvOS apps: with a symbol next to
            // every title the six tabs no longer fit the bar and it scrolls
            // sideways (Settings ends up cut off). TabBarLayoutUITests checks
            // that all six fit.
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Text("Home") }
                    .tag("home")
                    .navigationResetTab("home")
                LibraryView()
                    .tabItem { Text("Library") }
                    .tag("library")
                    .navigationResetTab("library")
                FavoritesView()
                    .tabItem { Text("Favorites") }
                    .tag("favorites")
                    .navigationResetTab("favorites")
                BookmarksView()
                    .tabItem { Text("Bookmarks") }
                    .tag("bookmarks")
                    .navigationResetTab("bookmarks")
                SearchView()
                    .tabItem { Text("Search") }
                    .tag("search")
                    .navigationResetTab("search")
                SettingsView()
                    .tabItem { Text("Settings") }
                    .tag("settings")
                    .navigationResetTab("settings")
            }
            .environment(navigationReset)
            .onChange(of: tab) { old, new in navigationReset.tabChanged(from: old, to: new) }
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
