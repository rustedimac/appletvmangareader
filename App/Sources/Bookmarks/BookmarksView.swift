import SwiftUI
import MangaCore

/// Every bookmarked page of the active profile, grouped by series, the
/// series with the newest bookmark first. Picking a bookmark opens the
/// reader on that page; holding select offers Remove and Go to Series.
struct BookmarksView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var reader: ReaderRoute?
    @State private var opening: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical) {
                let groups = BookmarkGroup.make(model.bookmarks)
                if groups.isEmpty {
                    BrowseMessage(title: "No bookmarks yet",
                                  message: "While reading, open the menu and choose Bookmark This Page. In the page reader you can also press up on the remote.",
                                  systemImage: "bookmark")
                } else {
                    LazyVStack(alignment: .leading, spacing: 50) {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("bookmarks.error")
                        }
                        ForEach(groups) { group in
                            section(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }
            }
            .seriesNavigation()
            .themedScreen()
        }
        .task { await model.syncAllBookmarks() }
        .fullScreenCover(item: $reader) { ReaderHost(route: $0) }
    }

    private func section(_ group: BookmarkGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(group.series.title).font(.headline)
                if model.servers.count > 1, let server = model.state.server(group.series.ref.serverID) {
                    Text(server.name).font(.callout).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("bookmarks.series.\(group.series.ref.seriesID)")
            ForEach(group.bookmarks) { bookmark in
                row(bookmark)
            }
        }
        .focusSection()
    }

    private func row(_ bookmark: Bookmark) -> some View {
        Button {
            Task { await open(bookmark) }
        } label: {
            HStack(spacing: 24) {
                Image(systemName: "bookmark.fill").foregroundStyle(.red).frame(width: 40)
                Text(bookmark.chapterTitle.isEmpty ? "Chapter" : bookmark.chapterTitle).lineLimit(1)
                Spacer()
                if opening == bookmark.id { ProgressView() }
                Text(bookmark.pageLabel).font(.callout).foregroundStyle(.secondary)
                Text(bookmark.createdAt, format: .dateTime.year().month().day())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("bookmark.\(bookmark.chapterID).\(bookmark.page)")
        .contextMenu {
            Button("Go to Series") { path.append(bookmark.series) }
            Button("Remove Bookmark", role: .destructive) { model.removeBookmark(bookmark) }
        }
    }

    /// Loads the series' chapters, then opens the reader on the page.
    private func open(_ bookmark: Bookmark) async {
        guard opening == nil else { return }
        opening = bookmark.id
        defer { opening = nil }
        do {
            let detail = try await model.seriesDetail(bookmark.series.ref)
            guard let chapter = detail.chapters.first(where: { $0.id == bookmark.chapterID }) else {
                errorMessage = "\(bookmark.chapterTitle.isEmpty ? "That chapter" : bookmark.chapterTitle) is no longer on the server."
                return
            }
            errorMessage = nil
            var series = bookmark.series
            series.libraryID = series.libraryID ?? detail.summary.libraryID
            reader = ReaderRoute(series: series, chapters: detail.chapters, start: chapter, startPage: bookmark.page)
            await model.didLoadSeriesDetail(detail)
        } catch {
            errorMessage = "Couldn't open \(bookmark.series.title): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}

/// One series' bookmarks for the Bookmarks tab.
struct BookmarkGroup: Identifiable {
    let series: SeriesSummary
    let bookmarks: [Bookmark]
    var id: SeriesRef { series.ref }

    /// Groups newest-first bookmarks by series, keeping that order between
    /// series and sorting each series' bookmarks by chapter and page.
    static func make(_ bookmarks: [Bookmark]) -> [BookmarkGroup] {
        var order: [SeriesRef] = []
        var bySeries: [SeriesRef: [Bookmark]] = [:]
        for b in bookmarks {
            if bySeries[b.series.ref] == nil { order.append(b.series.ref) }
            bySeries[b.series.ref, default: []].append(b)
        }
        return order.compactMap { ref in
            guard let items = bySeries[ref], let first = items.first else { return nil }
            let sorted = items.sorted {
                ($0.chapterNumber ?? .infinity, $0.page) < ($1.chapterNumber ?? .infinity, $1.page)
            }
            return BookmarkGroup(series: first.series, bookmarks: sorted)
        }
    }
}
