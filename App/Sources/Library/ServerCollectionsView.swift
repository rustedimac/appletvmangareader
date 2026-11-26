import SwiftUI
import MangaCore

// Reading lists, collections and smart filters (Kavita), read-only.
// Library shows a button for each kind the server supports beside its
// libraries; it opens a grid of that kind's lists. A collection or smart
// filter opens a series grid; a reading list opens its chapters in order.

/// The Library bar buttons for a server's list kinds. Nothing for servers
/// without any (Suwayomi, Komga, OPDS, Free Library).
struct ServerCollectionLinks: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig

    var body: some View {
        ForEach(model.client(for: server).collectionSupport.kinds, id: \.self) { kind in
            NavigationLink {
                ServerCollectionsView(server: server, kind: kind)
            } label: {
                Label(kind.title, systemImage: kind.symbolName)
            }
            .accessibilityIdentifier("library.collections.\(kind.rawValue)")
        }
    }
}

/// Every list of one kind on a server, as a grid of covers.
struct ServerCollectionsView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let kind: ServerCollectionKind

    @State private var items: [ServerCollection] = []
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("\(kind.title) · \(server.name)")
                    .font(.title3.bold())
                    .lineLimit(1)
                    .accessibilityIdentifier("collections.title")
                if let errorMessage {
                    BrowseMessage(title: "Couldn't load \(kind.title.lowercased())", message: errorMessage,
                                  systemImage: "wifi.exclamationmark") { Task { await load() } }
                } else if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(Space.xxl)
                } else if items.isEmpty {
                    BrowseMessage(title: "No \(kind.title.lowercased())", message: kind.emptyMessage,
                                  systemImage: kind.symbolName)
                        .emptyStateFocus()
                } else {
                    grid
                }
            }
            .padding(.bottom, Space.xl)
        }
        .task(id: model.contentKey(for: server)) { await load() }
    }

    private var grid: some View {
        let density = model.gridDensity
        let width = CGFloat(density.posterWidth)
        let columns = [GridItem(.adaptive(minimum: width, maximum: width + 20),
                                spacing: CGFloat(density.spacing), alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: CGFloat(density.spacing) + 8) {
            ForEach(items) { item in
                CollectionPoster(collection: item, server: server, width: width)
            }
        }
        .padding(.vertical, 30)
        .focusSection()
    }

    private func load() async {
        do {
            let list = try await model.client(for: server).collections(kind)
            guard !Task.isCancelled else { return }
            items = ServerCollection.sorted(list)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loaded = true
    }
}

/// A list's cover (or its title on a plain card), title and caption.
private struct CollectionPoster: View {
    @Environment(AppModel.self) private var model
    let collection: ServerCollection
    let server: ServerConfig
    let width: CGFloat
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                if collection.kind.holdsChapters {
                    ReadingListView(server: server, list: collection)
                } else {
                    CollectionSeriesView(server: server, collection: collection)
                }
            } label: {
                ZStack {
                    PosterImage(url: collection.coverURL, server: model.client(for: server), title: collection.title)
                    if collection.coverURL == nil {
                        Image(systemName: collection.kind.symbolName)
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.5))
                            .offset(y: -width * 0.4)
                    }
                }
                .frame(width: width, height: width * 1.5)
                .clipped()
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .accessibilityLabel(collection.title)
            .accessibilityValue(collection.caption ?? "")
            .accessibilityIdentifier("collection.\(collection.collectionID)")
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(width < PosterMetrics.width ? .caption2 : .caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = collection.caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .offset(y: isFocused ? PosterMetrics.focusedTitleDrop(forWidth: width) : 0)
            .animation(.easeOut(duration: 0.2), value: isFocused)
        }
    }
}

/// The title and summary at the top of a list's screen.
private struct CollectionHeader: View {
    let collection: ServerCollection
    let server: ServerConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(collection.title)
                .font(.title3.bold())
                .lineLimit(2)
                .accessibilityIdentifier("collection.title")
            Text([collection.kind.singularTitle, server.name, collection.caption]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let summary = collection.summary.map(SeriesDetailView.plainText), !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: Size.readableText, alignment: .leading)
                    .accessibilityIdentifier("collection.summary")
            }
        }
    }
}

/// The series in a collection or smart filter, a page at a time.
struct CollectionSeriesView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let collection: ServerCollection

    @State private var pager = LibraryPager<SeriesSummary>()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Space.m) {
                CollectionHeader(collection: collection, server: server)
                if pager.isEmpty {
                    BrowseMessage(title: "Nothing here",
                                  message: collection.kind == .smartFilter
                                      ? "No series match this filter."
                                      : "This collection has no series you can see.",
                                  systemImage: "tray")
                        .emptyStateFocus()
                } else {
                    SeriesGrid(series: pager.items) { index in
                        if pager.shouldLoadMore(afterShowing: index) { Task { await loadMore() } }
                    }
                }
                if let error = pager.errorMessage {
                    BrowseMessage(title: "Couldn't load the series", message: error, systemImage: "exclamationmark.triangle") {
                        pager.retry()
                        Task { await loadMore() }
                    }
                } else if pager.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(Space.l)
                }
            }
            .padding(.bottom, Space.xl)
        }
        .task(id: model.contentKey(for: server)) {
            pager.reset()
            await loadMore()
        }
    }

    private func loadMore() async {
        guard let ticket = pager.beginLoad() else { return }
        do {
            let page = try await model.client(for: server).series(in: collection, page: ticket.page,
                                                                  pageSize: pager.pageSize)
            pager.finish(ticket, page)
        } catch {
            pager.fail(ticket, error)
        }
    }
}

/// A reading list's chapters in list order. Continue opens the first one
/// not finished; each row opens its chapter, and its "…" goes to the series.
struct ReadingListView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let list: ServerCollection

    @State private var entries: [ReadingListEntry] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var reader: ReaderRoute?
    @State private var opening: String?
    @State private var openError: String?
    @FocusState private var focus: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Space.l) {
                CollectionHeader(collection: list, server: server)
                if let errorMessage {
                    BrowseMessage(title: "Couldn't load this list", message: errorMessage,
                                  systemImage: "exclamationmark.triangle") { Task { await load() } }
                } else if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(Space.xxl)
                } else if entries.isEmpty {
                    BrowseMessage(title: "This list is empty",
                                  message: "It has no chapters from the libraries you can see.", systemImage: "list.number")
                        .emptyStateFocus()
                } else {
                    if let resume = ReadingListEntry.resumeEntry(in: entries) {
                        ActionRow {
                            Button {
                                open(resume)
                            } label: {
                                Label(ReadingListEntry.resumeLabel(in: entries), systemImage: "play.fill")
                                    .actionButtonSizing()
                            }
                            .focused($focus, equals: "resume")
                            .accessibilityIdentifier("readingList.continue")
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            row(entry, position: index + 1)
                        }
                    }
                    .focusSection()
                }
            }
            .padding(.bottom, Space.xl)
        }
        .defaultFocus($focus, "resume")
        .task(id: model.contentKey(for: server)) { await load() }
        .fullScreenCover(item: $reader, onDismiss: { Task { await load() } }) { route in
            ReaderHost(route: route)
        }
        .alert("Couldn't open the chapter", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
    }

    private func row(_ entry: ReadingListEntry, position: Int) -> some View {
        HStack(spacing: Space.m) {
            Button {
                open(entry)
            } label: {
                HStack(spacing: Space.m) {
                    Text("\(position)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: Size.icon, alignment: .trailing)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(entry.title).lineLimit(1)
                        Text(entry.seriesTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let progress = entry.progress {
                            TitleProgressBar(fraction: progress)
                                .frame(maxWidth: 300)
                                .padding(.top, Space.xxs)
                        }
                    }
                    Spacer(minLength: Space.m)
                    if opening == entry.id {
                        ProgressView()
                    } else if entry.isRead {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(entry.isRead ? "read" : entry.progress.map { "\(Int(($0 * 100).rounded())) percent read" } ?? "unread")
            .accessibilityIdentifier("readingList.entry.\(entry.itemID)")
            // A destination link: this screen was pushed with one, and a
            // value link here doesn't reach the stack's SeriesSummary route.
            NavigationLink {
                SeriesDetailView(series: entry.seriesSummary)
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel("Go to \(entry.seriesTitle)")
            }
            .accessibilityIdentifier("readingList.series.\(entry.itemID)")
        }
        .frame(maxWidth: Size.formColumn + Size.heroColumn)
    }

    /// Loads the chapter's series (for the reader's chapter list and
    /// progress) and opens the reader at the chapter.
    private func open(_ entry: ReadingListEntry) {
        guard opening == nil else { return }
        opening = entry.id
        Task {
            defer { opening = nil }
            do {
                let detail = try await model.seriesDetail(entry.seriesRef)
                guard let chapter = detail.chapters.first(where: { $0.id == entry.chapterID }) else {
                    openError = "The chapter isn't in \(entry.seriesTitle) anymore."
                    return
                }
                var series = entry.seriesSummary
                series.coverURL = detail.summary.coverURL
                series.title = detail.summary.title.isEmpty ? series.title : detail.summary.title
                reader = ReaderRoute(series: series, chapters: detail.chapters, start: chapter)
            } catch {
                openError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func load() async {
        do {
            let fetched = try await model.client(for: server).readingListEntries(list)
            guard !Task.isCancelled else { return }
            entries = fetched
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if entries.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        loaded = true
    }
}

private extension View {
    /// An empty screen still needs something focused, or tvOS hands the
    /// Menu press to the tab bar instead of going back. The message takes
    /// focus without looking like a button.
    func emptyStateFocus() -> some View {
        focusable().centeredFocusRow()
    }
}
