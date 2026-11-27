import SwiftUI
import MangaCore

/// Server → categories (Kavita libraries, Suwayomi categories) → poster
/// grid. With one server the server list is skipped. Servers with reading
/// lists, collections or smart filters get a button for each in the
/// category bar (`ServerCollectionsView`).
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
            // The pushed value is a snapshot; show the server as it is now,
            // so an edit in Settings (address, login) applies right away.
            .navigationDestination(for: ServerConfig.self) { ServerLibraryView(server: model.state.server($0.id) ?? $0) }
            .browseMargins()
            .browseTitle("Library")
            .seriesNavigation()
            .themedScreen()
        }
        .resetsNavigationWhenLeft()
    }
}

private struct ServerListView: View {
    let servers: [ServerConfig]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Servers")
                    .themedSectionLabel(.headline, fallback: .headline)
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
    /// `model.contentKey(for:)` the categories were loaded for.
    @State private var loadedKey: String?
    @State private var jump: LetterJump?

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .center, spacing: platformValue(tv: 10, touch: Space.xs)) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: platformValue(tv: 20, touch: Space.m)) {
                        #if os(tvOS)
                        Text(server.name)
                            .themedHeading(.title3, fallback: .title3.bold())
                        #endif
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
                                let options = model.resolvedLibraryOptions(server, selected)
                                let filter = options.activeFilter.limited(to: model.client(for: server).libraryFilterSupport)
                                CategoryGridView(server: server, category: selected, options: options, filter: filter,
                                                 jump: jump, proxy: proxy)
                                    // A new login or selection reloads the grid from page 1.
                                    .id("\(selected.id)|\((options.sort ?? .default).rawValue)|\(filter.key)|\(loadedKey ?? "")")
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
        .task(id: model.contentKey(for: server)) {
            // After a change in Settings, show loading rather than the
            // libraries from before it.
            if loadedKey != model.contentKey(for: server) {
                loaded = false
                errorMessage = nil
            }
            await load()
        }
        .browseMargins()
        .browseTitle(server.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .themedScreen()
    }

    /// The A–Z bar only makes sense when the grid is sorted by title.
    private var showsJumpBar: Bool {
        guard loaded, errorMessage == nil, let selected else { return false }
        return (model.resolvedLibraryOptions(server, selected).sort ?? .default).isTitleOrder
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
                    .controlSelected(isSelected)
                    .accessibilityIdentifier("category.\(category.id)")
                    .accessibilityValue(isSelected ? "selected" : "")
                }
                if let selected {
                    let filters = model.resolvedLibraryOptions(server, selected).activeFilter
                        .limited(to: model.client(for: server).libraryFilterSupport).activeCount
                    NavigationLink {
                        LibraryOptionsView(server: server, category: selected)
                    } label: {
                        Label(filters == 0 ? "Sort & View" : "Sort & View (\(filters == 1 ? "1 filter" : "\(filters) filters"))",
                              systemImage: filters == 0 ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityIdentifier("library.options")
                    .accessibilityValue(filters == 0 ? "" : filters == 1 ? "1 filter" : "\(filters) filters")
                }
                // Reading lists, collections and smart filters (Kavita).
                ServerCollectionLinks(server: server)
                chooseLink
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .tvFocusSection()
    }

    private func load() async {
        let key = model.contentKey(for: server)
        do {
            let list = try await model.client(for: server).categories().sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            guard !Task.isCancelled else { return }
            categories = list
            loadedKey = key
            if selected == nil || !list.contains(where: { $0.id == selected?.id }) { selected = list.first }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            loadedKey = key
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
    /// Resolved (`AppModel.resolvedLibraryOptions`).
    let options: LibraryOptions
    /// Limited to what the server supports.
    let filter: LibraryFilter
    let jump: LetterJump?
    let proxy: ScrollViewProxy

    @State private var pager = LibraryPager<SeriesSummary>()
    @State private var isJumping = false
    @FocusState private var focused: SeriesRef?

    private var sort: LibrarySort { options.sort ?? .default }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if pager.isEmpty, !filter.isEmpty {
                BrowseMessage(title: "Nothing matches your filters",
                              message: "No series in \(category.name) match the filters in Sort & View.",
                              systemImage: "line.3.horizontal.decrease.circle")
                Button {
                    var own = model.libraryOptions(server, category)
                    own.filter = .empty
                    model.setLibraryOptions(own, server, category)
                } label: {
                    Label("Show Everything", systemImage: "xmark.circle")
                }
                .accessibilityIdentifier("library.clearFilters")
                .centeredFocusRow()
            } else if pager.isEmpty {
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
                                                                  pageSize: pager.pageSize, sort: sort, filter: filter)
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
