import SwiftUI
import MangaCore

/// Home rows in the profile's order (`HomeLayout`): Continue Reading,
/// Favorites, Recently Updated, Newly Added and Caught Up by default.
/// Server feeds get one row per server. Rows can be reordered or hidden in
/// "Customize Home", and long-pressing a Continue Reading poster removes it
/// from that row.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var sections: [HomeServerSection] = []
    @State private var loadedKey: String?
    /// Only the newest reload may replace the rows.
    @State private var generation = 0
    @State private var path = NavigationPath()

    enum Route: Hashable { case customize }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 40) {
                    content
                    NavigationLink(value: Route.customize) {
                        Label("Customize Home", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("home.customize")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
                .padding(.bottom, 60)
            }
            .seriesNavigation()
            .navigationDestination(for: Route.self) { _ in BrowseSettingsView() }
        }
        // Runs on every appear too, so coming back from another tab (after
        // reading from Library, or changing servers in Settings) reloads.
        .task(id: model.contentKey) { await reload() }
        .onChange(of: path.isEmpty) { _, isEmpty in
            // Back on Home after reading: progress and rows may have changed.
            if isEmpty { Task { await reload() } }
        }
    }

    private var isMultiServer: Bool { model.servers.count > 1 }
    /// Rows loaded for the current servers, libraries and profile. Rows
    /// from before a change in Settings aren't shown while the new ones
    /// load, so Home never mixes in a removed server or unticked library.
    private var currentSections: [HomeServerSection] {
        loadedKey == model.contentKey ? sections : []
    }
    private var isLoading: Bool { !model.servers.isEmpty && loadedKey != model.contentKey }

    @ViewBuilder
    private var content: some View {
        if model.servers.isEmpty {
            BrowseMessage(title: "No servers yet",
                          message: "Add a Kavita or Suwayomi server in Settings to start reading.",
                          systemImage: "server.rack")
        }
        ForEach(currentSections.filter { $0.errorMessage != nil }) { section in
            if section.errorMessage == MangaError.missingCredential.errorDescription {
                // Not a network problem: this profile hasn't signed in here yet.
                BrowseMessage(title: "\(model.activeProfile.name) isn't signed in to \(section.server.name)",
                              message: "Add a login for this profile in Settings → Servers → \(section.server.name).",
                              systemImage: "person.crop.circle.badge.exclamationmark")
            } else {
                BrowseMessage(title: "Couldn't reach \(section.server.name)", message: section.errorMessage ?? "",
                              systemImage: "wifi.exclamationmark") { Task { await reload() } }
            }
        }
        ForEach(model.homeLayout.visibleRows) { kind in
            rows(for: kind)
        }
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(80)
        } else if !model.servers.isEmpty && !hasAnyRow {
            BrowseMessage(title: "Nothing here yet",
                          message: model.homeLayout.visibleRows.isEmpty
                              ? "Every Home row is hidden. Choose Customize Home to bring them back."
                              : "Series you read, favorite or add to your servers show up here.",
                          systemImage: "house")
        }
    }

    @ViewBuilder
    private func rows(for kind: HomeRowKind) -> some View {
        switch kind {
        case .favorites:
            let favorites = model.favorites.map(\.series)
            if !favorites.isEmpty {
                SeriesShelf(title: kind.title, series: favorites, identifier: "favorites", showsServer: true)
            }
        case .caughtUp:
            let caughtUp = model.caughtUpSeries
            if !caughtUp.isEmpty {
                SeriesShelf(title: kind.title, series: caughtUp, identifier: "caughtUp", showsServer: true)
            }
        case .continueReading, .recentlyUpdated, .newlyAdded:
            if let feed = kind.feed {
                ForEach(currentSections) { section in
                    let series = self.series(feed, in: section)
                    if !series.isEmpty {
                        SeriesShelf(title: isMultiServer ? "\(kind.title) · \(section.server.name)" : kind.title,
                                    series: series,
                                    identifier: "\(section.server.name).\(feed.rawValue)",
                                    onRemove: feed == .continueReading ? removeFromContinueReading : nil)
                    }
                }
            }
        }
    }

    private var removeFromContinueReading: (SeriesSummary) -> Void {
        let model = self.model
        return { model.removeFromContinueReading($0.ref) }
    }

    private func series(_ feed: HomeFeed, in section: HomeServerSection) -> [SeriesSummary] {
        let series = section.rows.first { $0.feed == feed }?.series ?? []
        return feed == .continueReading ? model.filterContinueReading(series) : series
    }

    /// Whether any visible row has something in it.
    private var hasAnyRow: Bool {
        model.homeLayout.visibleRows.contains { kind in
            switch kind {
            case .favorites: return !model.favorites.isEmpty
            case .caughtUp: return !model.caughtUpSeries.isEmpty
            case .continueReading, .recentlyUpdated, .newlyAdded:
                guard let feed = kind.feed else { return false }
                return currentSections.contains { !series(feed, in: $0).isEmpty }
            }
        }
    }

    private func reload() async {
        let key = model.contentKey
        generation += 1
        let mine = generation
        let sources = model.servers.map {
            HomeSource(server: model.client(for: $0), includeContinueReading: model.syncsProgress(to: $0.id))
        }
        let loaded = await HomeLoader.load(sources)
        guard !Task.isCancelled, mine == generation else { return }
        sections = loaded
        loadedKey = key
        // A Caught Up series that shows up with unread chapters isn't anymore.
        model.pruneCaughtUp(seenIn: loaded.flatMap { $0.rows.flatMap(\.series) })
    }
}
