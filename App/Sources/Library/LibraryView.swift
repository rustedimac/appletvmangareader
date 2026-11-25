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
                            Image(systemName: server.kind.symbolName)
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

/// One server: a row of category buttons above the selected category's
/// grid, with an A–Z jump bar beside title-sorted grids.
struct ServerLibraryView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig

    @State private var categories: [MangaCategory] = []
    @State private var selected: MangaCategory?
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var jump: LetterJump?

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .center, spacing: 10) {
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
                            chooseLink.centeredFocusRow()
                        } else {
                            categoryBar
                            if let selected {
                                let options = model.libraryOptions(server, selected)
                                CategoryGridView(server: server, category: selected, options: options, jump: jump, proxy: proxy)
                                    .id("\(selected.id)|\((options.sort ?? .default).rawValue)")
                            }
                        }
                    }
                    .padding(.bottom, 60)
                }
                if showsJumpBar {
                    AlphabetJumpBar { jump = LetterJump(letter: $0) }
                }
            }
        }
        .task(id: "\(server.id)|\(server.baseURL)|\(model.scopeKey(for: server))") { await load() }
    }

    /// The A–Z bar only makes sense when the grid is sorted by title.
    private var showsJumpBar: Bool {
        guard loaded, errorMessage == nil, let selected else { return false }
        return (model.libraryOptions(server, selected).sort ?? .default).isTitleOrder
    }

    /// Opens the picker for which libraries/categories this profile imports.
    private var chooseLink: some View {
        NavigationLink {
            CategorySelectionView(server: server)
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
                if let selected {
                    NavigationLink {
                        LibraryOptionsView(server: server, category: selected)
                    } label: {
                        Label("Sort & View", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("library.options")
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

/// A press on the A–Z bar. Each press is new, so the same letter twice
/// jumps twice.
struct LetterJump: Equatable {
    let letter: String
    let id = UUID()
}

/// A category's series in the library's sort order, loaded a page at a
/// time as the user scrolls. Fills right to left for right-to-left
/// libraries.
private struct CategoryGridView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let category: MangaCategory
    let options: LibraryOptions
    let jump: LetterJump?
    let proxy: ScrollViewProxy

    @State private var pager = LibraryPager<SeriesSummary>()
    @State private var isJumping = false
    @FocusState private var focused: SeriesRef?

    private var sort: LibrarySort { options.sort ?? .default }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if pager.isEmpty {
                BrowseMessage(title: "\(category.name) is empty", systemImage: "tray")
            } else {
                SeriesGrid(series: pager.items, rightToLeft: options.gridIsRightToLeft, focus: $focused) { index in
                    if pager.shouldLoadMore(afterShowing: index) { Task { await loadMore() } }
                }
            }
            if let error = pager.errorMessage {
                BrowseMessage(title: "Couldn't load more", message: error, systemImage: "exclamationmark.triangle") {
                    pager.retry()
                    Task { await loadMore() }
                }
            } else if pager.isLoading || isJumping {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .task { await loadMore() }
        .onChange(of: jump) { _, request in
            guard let request else { return }
            Task { await perform(request) }
        }
    }

    private func loadMore() async {
        guard let ticket = pager.beginLoad() else { return }
        do {
            let page = try await model.client(for: server).series(in: category, page: ticket.page,
                                                                  pageSize: pager.pageSize, sort: sort)
            pager.finish(ticket, page)
        } catch {
            pager.fail(ticket, error)
        }
    }

    /// Loads pages until the letter is reached, then scrolls there and
    /// focuses the first poster at or after it.
    private func perform(_ request: LetterJump) async {
        guard sort.isTitleOrder else { return }
        isJumping = true
        defer { isJumping = false }
        var target: Int?
        var attempts = 0
        while target == nil, attempts < 500 {
            attempts += 1
            switch AlphabetIndex.jump(to: request.letter, in: pager.items.map(\.title),
                                      descending: sort == .titleDescending, hasMore: pager.hasMore) {
            case .index(let i):
                target = i
            case .none:
                return
            case .needsMore:
                if pager.errorMessage != nil { return }
                if pager.isLoading {
                    try? await Task.sleep(for: .milliseconds(100))
                } else {
                    await loadMore()
                }
            }
        }
        guard let target, pager.items.indices.contains(target) else { return }
        let ref = pager.items[target].ref
        // Posters from a page that just arrived aren't laid out yet; give
        // the grid a moment, then scroll again once they are.
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation { proxy.scrollTo(ref, anchor: .top) }
        try? await Task.sleep(for: .milliseconds(350))
        proxy.scrollTo(ref, anchor: .top)
        try? await Task.sleep(for: .milliseconds(150))
        focused = ref
    }
}
