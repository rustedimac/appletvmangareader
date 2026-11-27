import SwiftUI
import MangaCore

/// Searches every server at once. Results are grouped by server.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [ServerSearchResults] = []
    @State private var searchedQuery: String?
    @State private var isSearching = false
    @State private var searchedContentKey: String?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 40) {
                    content
                }
                .padding(.bottom, 60)
            }
            .searchable(text: $query, prompt: "Series title")
            .browseMargins()
            .browseTitle("Search")
            .seriesNavigation()
            .themedScreen()
        }
        .resetsNavigationWhenLeft()
        .task(id: "\(model.contentKey)|\(query)") {
            // Results from before a server or library change are dropped.
            if searchedContentKey != model.contentKey { results = [] }
            // Wait for typing to pause before hitting every server.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await run(query)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.servers.isEmpty {
            BrowseMessage(title: "No servers yet", message: "Add a server in Settings to search it.",
                          systemImage: "server.rack")
        } else if CrossServerSearch.normalize(query) == nil {
            BrowseMessage(title: "Search your servers",
                          message: Platform.isTV ? "Type a title, or hold the microphone button on the Siri Remote and say it."
                                                 : "Type a title, or tap the microphone on the keyboard and say it.",
                          systemImage: "mic")
                .accessibilityIdentifier("search.hint")
        } else if isSearching && results.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(80)
        } else if results.isEmpty && searchedQuery != nil {
            BrowseMessage(title: "No results", message: "Nothing matched “\(searchedQuery ?? "")” on your servers.",
                          systemImage: "magnifyingglass")
        } else {
            ForEach(results) { group in
                if let error = group.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.server.name).font(.headline).foregroundStyle(.secondary)
                        Text(error).font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    SeriesShelf(title: "\(group.server.name) (\(group.series.count))", series: group.series,
                                identifier: "search.\(group.server.name)")
                }
            }
        }
    }

    private func run(_ text: String) async {
        guard let q = CrossServerSearch.normalize(text) else {
            results = []
            searchedQuery = nil
            return
        }
        isSearching = true
        let key = model.contentKey
        let servers = model.servers.map { model.client(for: $0) }
        let found = await CrossServerSearch.run(q, on: servers)
        guard !Task.isCancelled else { return }
        results = found
        searchedQuery = q
        searchedContentKey = key
        isSearching = false
    }
}
