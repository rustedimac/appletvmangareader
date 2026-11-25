import SwiftUI
import MangaCore

/// Server → categories (Kavita libraries, Suwayomi categories) → poster
/// grid. With one server the server list is skipped.
struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.servers.isEmpty {
                    BrowseMessage(title: "No servers yet",
                                  message: "Add a Kavita or Suwayomi server in Settings to browse its library.",
                                  systemImage: "server.rack")
                } else if model.servers.count == 1, let server = model.servers.first {
                    ServerLibraryView(server: server)
                } else {
                    ServerListView(servers: model.servers)
                }
            }
            .navigationDestination(for: ServerConfig.self) { ServerLibraryView(server: $0) }
            .seriesNavigation()
        }
    }
}

private struct ServerListView: View {
    let servers: [ServerConfig]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Servers")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(servers) { server in
                    NavigationLink(value: server) {
                        HStack(spacing: 24) {
                            Image(systemName: server.kind == .kavita ? "books.vertical.fill" : "square.stack.3d.up.fill")
                                .frame(width: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                Text(server.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 1000)
                    }
                    .accessibilityIdentifier("library.server.\(server.name)")
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
}

/// One server: a row of category buttons above the selected category's grid.
struct ServerLibraryView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig

    @State private var categories: [MangaCategory] = []
    @State private var selected: MangaCategory?
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                Text(server.name)
                    .font(.title3.bold())
                if let errorMessage {
                    BrowseMessage(title: "Couldn't reach \(server.name)", message: errorMessage,
                                  systemImage: "wifi.exclamationmark") { Task { await load() } }
                } else if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(80)
                } else if categories.isEmpty {
                    BrowseMessage(title: "Nothing to browse",
                                  message: model.selectedCategories(for: server) == nil
                                      ? "This server has no libraries or categories that your account can see."
                                      : "None of the \(server.kind.categoryNoun.lowercased()) you picked are on this server anymore.")
                    chooseLink.frame(maxWidth: .infinity)
                } else {
                    categoryBar
                    if let selected {
                        CategoryGridView(server: server, category: selected)
                            .id(selected.id)
                    }
                }
            }
            .padding(.bottom, 60)
        }
        .task(id: "\(server.id)|\(server.baseURL)|\(model.scopeKey(for: server))") { await load() }
    }

    /// Opens the picker for which libraries/categories this profile imports.
    private var chooseLink: some View {
        NavigationLink {
            PINGate(kind: .profile(model.activeProfile.id), reason: "Enter the PIN to change what this profile imports.") {
                CategorySelectionView(server: server)
            }
        } label: {
            Label("Choose \(server.kind.categoryNoun)", systemImage: "checklist")
        }
        .accessibilityIdentifier("library.chooseCategories")
    }

    private var categoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(categories) { category in
                    let isSelected = category.id == selected?.id
                    Button {
                        selected = category
                    } label: {
                        Text(category.name)
                            .fontWeight(isSelected ? .bold : .regular)
                    }
                    .tint(isSelected ? Color.accentColor : nil)
                    .accessibilityIdentifier("category.\(category.id)")
                    .accessibilityValue(isSelected ? "selected" : "")
                }
                chooseLink
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private func load() async {
        do {
            let list = try await model.client(for: server).categories().sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            categories = list
            if selected == nil || !list.contains(where: { $0.id == selected?.id }) { selected = list.first }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loaded = true
    }
}

/// A category's series, loaded a page at a time as the user scrolls.
private struct CategoryGridView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let category: MangaCategory

    @State private var pager = LibraryPager<SeriesSummary>()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if pager.isEmpty {
                BrowseMessage(title: "\(category.name) is empty", systemImage: "tray")
            } else {
                SeriesGrid(series: pager.items) { index in
                    if pager.shouldLoadMore(afterShowing: index) { Task { await loadMore() } }
                }
            }
            if let error = pager.errorMessage {
                BrowseMessage(title: "Couldn't load more", message: error, systemImage: "exclamationmark.triangle") {
                    pager.retry()
                    Task { await loadMore() }
                }
            } else if pager.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .task { await loadMore() }
    }

    private func loadMore() async {
        guard let ticket = pager.beginLoad() else { return }
        do {
            let page = try await model.client(for: server).series(in: category, page: ticket.page, pageSize: pager.pageSize)
            pager.finish(ticket, page)
        } catch {
            pager.fail(ticket, error)
        }
    }
}
