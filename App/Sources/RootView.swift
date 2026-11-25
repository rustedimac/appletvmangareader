import SwiftUI
import MangaCore

/// Top-level tabs. Each tab's folder under App/Sources is owned by one
/// workstream; replace the placeholder views there.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = UITestingSeed.initialTab ?? "home"

    var body: some View {
        content
            // PINs are asked for again after the app has been away.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.lockAll() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isPickingProfile {
            ProfilePickerView()
        } else {
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag("home")
                LibraryView()
                    .tabItem { Label("Library", systemImage: "books.vertical") }
                    .tag("library")
                FavoritesView()
                    .tabItem { Label("Favorites", systemImage: "heart") }
                    .tag("favorites")
                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag("search")
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
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
