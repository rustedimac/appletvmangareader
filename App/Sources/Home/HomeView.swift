import SwiftUI
import MangaCore

/// Favorites first, then one block per server with Continue Reading,
/// Recently Updated and Newly Added rows.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var sections: [HomeServerSection] = []
    @State private var loadedKey: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 40) {
                    content
                }
                .padding(.bottom, 60)
            }
            .seriesNavigation()
        }
        .task(id: reloadKey) { await reload() }
        .onChange(of: path.isEmpty) { _, isEmpty in
            // Back on Home after reading: progress and rows may have changed.
            if isEmpty { Task { await reload() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        let favorites = model.favorites.map(\.series)
        if !favorites.isEmpty {
            SeriesShelf(title: "Favorites", series: favorites, identifier: "favorites", showsServer: true)
        }
        if model.servers.isEmpty {
            BrowseMessage(title: "No servers yet",
                          message: "Add a Kavita or Suwayomi server in Settings to start reading.",
                          systemImage: "server.rack")
        } else if sections.isEmpty && loadedKey != reloadKey {
            ProgressView().frame(maxWidth: .infinity).padding(80)
        } else {
            ForEach(sections) { section in
                serverSection(section)
            }
        }
    }

    @ViewBuilder
    private func serverSection(_ section: HomeServerSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.servers.count > 1 {
                Text(section.server.name)
                    .font(.title3.bold())
                    .accessibilityIdentifier("home.server.\(section.server.name)")
            }
            if let error = section.errorMessage {
                BrowseMessage(title: "Couldn't reach \(section.server.name)", message: error,
                              systemImage: "wifi.exclamationmark") { Task { await reload() } }
            } else if section.rows.isEmpty {
                Text("Nothing here yet.").foregroundStyle(.secondary)
            } else {
                ForEach(section.rows) { row in
                    SeriesShelf(title: row.feed.title, series: row.series,
                                identifier: "\(section.server.name).\(row.feed.rawValue)")
                }
            }
        }
    }

    private var reloadKey: String {
        ([model.activeProfile.id.uuidString] + model.servers.map { "\($0.id)|\($0.baseURL)|\($0.name)|\(model.scopeKey(for: $0))" })
            .joined(separator: ",")
    }

    private func reload() async {
        let key = reloadKey
        let sources = model.servers.map {
            HomeSource(server: model.client(for: $0), includeContinueReading: model.syncsProgress(to: $0.id))
        }
        let loaded = await HomeLoader.load(sources)
        guard !Task.isCancelled else { return }
        sections = loaded
        loadedKey = key
    }
}
