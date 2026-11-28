import SwiftUI
import MangaCore

/// Cover, synopsis, genres, a favorite toggle, Continue/Start, and the
/// chapter list. Chapters open the reader full screen. Each chapter row has
/// a "…" button to its right (and the same items on a long press) with Mark
/// as Read, Mark as Unread and Mark Previous as Read; the "More" button
/// marks the whole series. The "…" button means none of this needs a long
/// press, which is easy to miss on the remote and in the Simulator.
struct SeriesDetailView: View {
    @Environment(AppModel.self) private var model
    let series: SeriesSummary

    @State private var detail: SeriesDetail?
    @State private var errorMessage: String?
    @State private var newestFirst = false
    @State private var reader: ReaderRoute?
    @State private var markError: MarkError?
    /// Which libraries/categories of its server the series is in.
    @State private var placement: SeriesPlacement?

    private struct MarkError: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }
    @FocusState private var focus: Field?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private enum Field: Hashable { case primary }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: platformValue(tv: 50, touch: Space.xl)) {
                header
                if let detail {
                    SeriesBookmarksSection(series: series.ref, chapters: detail.chapters) { open($0, page: $1) }
                    chapterList(detail)
                } else if let errorMessage {
                    BrowseMessage(title: "Couldn't load this series", message: errorMessage,
                                  systemImage: "exclamationmark.triangle") { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, platformValue(tv: 20, touch: Space.l))
            .padding(.bottom, platformValue(tv: 60, touch: Space.xl))
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .defaultFocus($focus, .primary)
        .task { await load() }
        .fullScreenCover(item: $reader, onDismiss: {
            // After the reader's last save lands, or the server answers
            // with the old page.
            Task {
                await model.waitForProgressSaves(series.ref)
                await load()
            }
        }) { route in
            ReaderHost(route: route)
        }
        .alert(markError?.title ?? "", isPresented: Binding(get: { markError != nil }, set: { if !$0 { markError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(markError?.message ?? "")
        }
    }

    private var summary: SeriesSummary {
        // Keep the summary we navigated with (it has the library id and
        // cover), but take a better title from detail when there is one.
        var s = series
        if let d = detail?.summary {
            s.title = d.title.isEmpty ? s.title : d.title
            s.coverURL = s.coverURL ?? d.coverURL
            s.libraryID = s.libraryID ?? d.libraryID
            s.unreadCount = d.unreadCount ?? s.unreadCount
        }
        return s
    }

    @ViewBuilder
    private var header: some View {
        #if os(tvOS)
        HStack(alignment: .top, spacing: 60) {
            cover(width: 360)
            VStack(alignment: .leading, spacing: 20) {
                titleBlock
                aboutBlock
                actions.padding(.top, 10)
            }
        }
        .tvFocusSection()
        #else
        // iPhone, compact iPad windows: a small cover beside the title, the
        // rest full width below. Regular width: the TV layout, smaller.
        if sizeClass == .compact {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .top, spacing: Space.l) {
                    cover(width: 120)
                    VStack(alignment: .leading, spacing: Space.s) { titleBlock }
                }
                aboutBlock
                actions
            }
        } else {
            HStack(alignment: .top, spacing: Space.xl) {
                cover(width: 220)
                VStack(alignment: .leading, spacing: Space.m) {
                    titleBlock
                    aboutBlock
                    actions.padding(.top, Space.s)
                }
            }
        }
        #endif
    }

    private func cover(width: CGFloat) -> some View {
        PosterImage(url: summary.coverURL, server: model.client(for: series.ref), title: summary.title)
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: Radius.poster))
            .shadow(radius: platformValue(tv: 20, touch: 8))
    }

    /// Title, authors and status, and where the series lives.
    @ViewBuilder
    private var titleBlock: some View {
        Text(summary.title)
            .font(.title2.bold())
            .lineLimit(2)
            .accessibilityIdentifier("series.title")
        if let line = metaLine, !line.isEmpty {
            Text(line).foregroundStyle(.secondary)
        }
        if let server = model.state.server(series.ref.serverID),
           let location = SeriesPlacement.line(server: server.name, placement: placement) {
            // "kavita-en.home · Manga": the server and the library or
            // categories the series is in there.
            Label(location, systemImage: server.kind.symbolName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(location)
                .accessibilityIdentifier("series.location")
        }
    }

    /// Genres, synopsis and how much is read.
    @ViewBuilder
    private var aboutBlock: some View {
        if let genres = detail?.genres, !genres.isEmpty {
            Text(genres.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let synopsis = detail?.synopsis.map(Self.plainText), !synopsis.isEmpty {
            Text(synopsis)
                .font(.callout)
                .lineLimit(5)
                .frame(maxWidth: 1100, alignment: .leading)
                .accessibilityIdentifier("series.synopsis")
        }
        if model.browsePreferences.showsProgressPercent, let detail,
           let read = PosterBadges.readText(detail: detail, summary: series) {
            // "42% read", next to Continue, so checking how far
            // along a series is doesn't need a trip back out.
            Text(read)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .accessibilityIdentifier("series.percentRead")
        }
    }

    private var metaLine: String? {
        guard let detail else { return nil }
        var parts: [String] = []
        if !detail.authors.isEmpty { parts.append(detail.authors.joined(separator: ", ")) }
        if let status = detail.status, !status.isEmpty { parts.append(status) }
        if let format = (detail.summary.format ?? series.format), format != .images { parts.append(format.displayName) }
        parts.append("\(detail.readCount) of \(detail.chapters.count) read")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        #if os(tvOS)
        HStack(spacing: 30) {
            continueButton
            favoriteButton
            sortButton
            moreMenu
        }
        #else
        // Touch: Continue is the one prominent button, full width on a
        // phone; the rest sit under it as bordered buttons.
        VStack(alignment: .leading, spacing: Space.m) {
            continueButton
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: sizeClass == .compact ? .infinity : nil)
            HStack(spacing: Space.m) {
                favoriteButton
                sortButton
                moreMenu
            }
            .buttonStyle(.bordered)
        }
        #endif
    }

    @ViewBuilder
    private var continueButton: some View {
        if let action = detail?.continueAction {
            Button {
                open(action.chapter)
            } label: {
                Label(action.label, systemImage: "play.fill")
                    .lineLimit(1)
                    #if os(iOS)
                    .frame(maxWidth: sizeClass == .compact ? .infinity : nil)
                    #endif
            }
            .focused($focus, equals: .primary)
            .accessibilityIdentifier("series.continue")
        }
    }

    private var favoriteButton: some View {
        let favorite = model.isFavorite(series.ref)
        return Button {
            model.toggleFavorite(summary)
        } label: {
            Label(favorite ? "Favorited" : "Favorite", systemImage: favorite ? "heart.fill" : "heart")
        }
        .accessibilityIdentifier("series.favorite")
        .accessibilityValue(favorite ? "on" : "off")
    }

    @ViewBuilder
    private var sortButton: some View {
        if let detail, detail.chapters.count > 1 {
            Button {
                newestFirst.toggle()
            } label: {
                Label(newestFirst ? "Newest First" : "Oldest First", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("series.sort")
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        if let detail {
            Menu {
                Button {
                    markRead(detail.chapters.filter { !$0.isRead })
                } label: {
                    Label("Mark Series as Read", systemImage: "checkmark.circle")
                }
                .disabled(detail.chapters.allSatisfy(\.isRead))
                .accessibilityIdentifier("series.more.read")
                Button {
                    markUnread(nil)
                } label: {
                    Label("Mark Series as Unread", systemImage: "circle")
                }
                .disabled(!detail.hasProgress)
                .accessibilityIdentifier("series.more.unread")
            } label: {
                Label("More", systemImage: "ellipsis")
                    #if os(iOS)
                    .labelStyle(.iconOnly)
                    #endif
            }
            .accessibilityIdentifier("series.more")
        }
    }

    @ViewBuilder
    private func chapterList(_ detail: SeriesDetail) -> some View {
        if detail.chapters.isEmpty {
            BrowseMessage(title: "No chapters", message: "This series has no chapters on the server yet.",
                          systemImage: "doc")
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Chapters")
                    .font(.headline).foregroundStyle(.secondary)
                ForEach(detail.displayChapters(newestFirst: newestFirst)) { chapter in
                    let earlier = detail.chapters(before: chapter)
                    ChapterRow(chapter: chapter, seriesHasProgress: detail.hasProgress,
                               hasUnreadBefore: earlier.contains { !$0.isRead },
                               open: { open(chapter) },
                               markRead: { markRead([chapter]) },
                               markUnread: { markUnread([chapter]) },
                               markPreviousRead: { markRead(earlier.filter { !$0.isRead }) },
                               markSeriesUnread: { markUnread(nil) })
                }
            }
            .tvFocusSection()
        }
    }

    private func open(_ chapter: Chapter, page: Int? = nil) {
        guard let detail else { return }
        reader = ReaderRoute(series: summary, chapters: detail.chapters, start: chapter, startPage: page)
    }

    /// Shows the chapters as read right away, then saves and reloads.
    private func markRead(_ chapters: [Chapter]) {
        guard let detail, !chapters.isEmpty else { return }
        self.detail = detail.markingRead(Set(chapters.map(\.id)))
        Task {
            do {
                try await model.markRead(chapters, in: series.ref, libraryID: summary.libraryID)
            } catch {
                markError = MarkError(title: "Couldn't mark as read",
                                      message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            await load()
        }
    }

    /// Shows the chapters (nil: the whole series) as unread right away,
    /// then saves and reloads from the server.
    private func markUnread(_ chapters: [Chapter]?) {
        guard let detail else { return }
        self.detail = detail.markingUnread(chapters.map { Set($0.map(\.id)) })
        Task {
            do {
                if let chapters {
                    try await model.markUnread(chapters, in: series.ref)
                } else {
                    try await model.markSeriesUnread(series.ref)
                }
            } catch {
                markError = MarkError(title: "Couldn't mark as unread",
                                      message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            await load()
        }
    }

    private func load() async {
        do {
            let firstLoad = detail == nil
            let loaded = try await model.seriesDetail(series.ref)
            detail = loaded
            model.noteSeriesDetail(loaded, summary: summary)
            errorMessage = nil
            if firstLoad { focus = .primary }
            if let client = model.client(for: series.ref),
               let found = await client.placement(for: series, detail: loaded) {
                placement = found
            }
            await model.didLoadSeriesDetail(loaded)
        } catch {
            if detail == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Kavita synopses can contain HTML.
    static func plainText(_ s: String) -> String {
        s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChapterRow: View {
    let chapter: Chapter
    let seriesHasProgress: Bool
    /// Some chapter before this one is unread.
    let hasUnreadBefore: Bool
    let open: () -> Void
    let markRead: () -> Void
    let markUnread: () -> Void
    let markPreviousRead: () -> Void
    let markSeriesUnread: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Button(action: open) {
                #if os(tvOS)
                HStack(spacing: 24) {
                    Image(systemName: icon)
                        .checkMarkStyle(!chapter.isRead)
                        .frame(width: 40)
                    Text(chapter.title)
                        .lineLimit(1)
                        .foregroundStyle(chapter.isRead ? Color.secondary : Color.primary)
                    Spacer()
                    if let badge = chapter.format?.badge {
                        FormatBadge(text: badge)
                    }
                    Text(chapter.rowDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let date = chapter.updatedAt {
                        Text(date, format: .dateTime.year().month().day())
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                #else
                // Touch: the details go under the title so long titles
                // keep their room on a phone.
                HStack(spacing: Space.m) {
                    Image(systemName: icon)
                        .checkMarkStyle(!chapter.isRead)
                        .frame(width: Size.icon)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(chapter.title)
                            .lineLimit(2)
                            .foregroundStyle(chapter.isRead ? Color.secondary : Color.primary)
                        Text(touchDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let badge = chapter.format?.badge {
                        FormatBadge(text: badge)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Size.minTarget)
                .contentShape(Rectangle())
                #endif
            }
            #if os(iOS)
            .buttonStyle(PressDimButtonStyle())
            #endif
            .accessibilityIdentifier("chapter.\(chapter.id)")
            .accessibilityValue(chapter.readState == .read ? "read" : chapter.readState == .unread ? "unread" : "in progress")
            .contextMenu { items(prefix: "chapter.menu") }

            // The same items without a long press: move right, then click.
            Menu {
                items(prefix: "chapter.actions")
            } label: {
                Label("Chapter Options", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("chapterOptions.\(chapter.id)")
            .accessibilityLabel("Options for \(chapter.title)")
        }
    }

    @ViewBuilder
    private func items(prefix: String) -> some View {
        if chapter.readState != .read {
            Button(action: markRead) {
                Label("Mark as Read", systemImage: "checkmark.circle")
            }
            .accessibilityIdentifier("\(prefix).read")
        }
        if chapter.readState != .unread {
            Button(action: markUnread) {
                Label("Mark as Unread", systemImage: "circle")
            }
            .accessibilityIdentifier("\(prefix).unread")
        }
        if hasUnreadBefore {
            Button(action: markPreviousRead) {
                Label("Mark Previous as Read", systemImage: "text.badge.checkmark")
            }
            .accessibilityIdentifier("\(prefix).previousRead")
        }
        Button(action: markSeriesUnread) {
            Label("Mark Series as Unread", systemImage: "circle.dashed")
        }
        .disabled(!seriesHasProgress)
        .accessibilityIdentifier("\(prefix).seriesUnread")
    }

    #if os(iOS)
    /// "20 pages · Nov 15, 2023"
    private var touchDetail: String {
        var parts = [chapter.rowDetail]
        if let date = chapter.updatedAt { parts.append(date.formatted(.dateTime.year().month().day())) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    #endif

    private var icon: String {
        switch chapter.readState {
        case .read: return "checkmark.circle.fill"
        case .inProgress: return "circle.lefthalf.filled"
        case .unread: return "circle"
        }
    }
}
