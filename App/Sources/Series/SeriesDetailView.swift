import SwiftUI
import MangaCore

/// Cover, synopsis, genres, a favorite toggle, Continue/Start, and the
/// chapter list. Chapters open the reader full screen. Long-pressing a
/// chapter, or the "More" button, offers Mark as Unread.
struct SeriesDetailView: View {
    @Environment(AppModel.self) private var model
    let series: SeriesSummary

    @State private var detail: SeriesDetail?
    @State private var errorMessage: String?
    @State private var newestFirst = false
    @State private var reader: ReaderRoute?
    @State private var markError: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case primary }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 50) {
                header
                if let detail {
                    chapterList(detail)
                } else if let errorMessage {
                    BrowseMessage(title: "Couldn't load this series", message: errorMessage,
                                  systemImage: "exclamationmark.triangle") { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
        .defaultFocus($focus, .primary)
        .task { await load() }
        .fullScreenCover(item: $reader, onDismiss: { Task { await load() } }) { route in
            ReaderHost(route: route)
        }
        .alert("Couldn't mark as unread", isPresented: Binding(get: { markError != nil }, set: { if !$0 { markError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(markError ?? "")
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

    private var header: some View {
        HStack(alignment: .top, spacing: 60) {
            PosterImage(url: summary.coverURL, server: model.client(for: series.ref), title: summary.title)
                .frame(width: 360, height: 540)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 20)

            VStack(alignment: .leading, spacing: 20) {
                Text(summary.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .accessibilityIdentifier("series.title")
                if let line = metaLine, !line.isEmpty {
                    Text(line).foregroundStyle(.secondary)
                }
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
                }
                actions.padding(.top, 10)
            }
        }
        .focusSection()
    }

    private var metaLine: String? {
        guard let detail else { return model.state.server(series.ref.serverID)?.name }
        var parts: [String] = []
        if !detail.authors.isEmpty { parts.append(detail.authors.joined(separator: ", ")) }
        if let status = detail.status, !status.isEmpty { parts.append(status) }
        parts.append("\(detail.readCount) of \(detail.chapters.count) read")
        if let server = model.state.server(series.ref.serverID) { parts.append(server.name) }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 30) {
            if let action = detail?.continueAction {
                Button {
                    open(action.chapter)
                } label: {
                    Label(action.label, systemImage: "play.fill")
                        .lineLimit(1)
                }
                .focused($focus, equals: .primary)
                .accessibilityIdentifier("series.continue")
            }

            let favorite = model.isFavorite(series.ref)
            Button {
                model.toggleFavorite(summary)
            } label: {
                Label(favorite ? "Favorited" : "Favorite", systemImage: favorite ? "heart.fill" : "heart")
            }
            .accessibilityIdentifier("series.favorite")
            .accessibilityValue(favorite ? "on" : "off")

            if let detail, detail.chapters.count > 1 {
                Button {
                    newestFirst.toggle()
                } label: {
                    Label(newestFirst ? "Newest First" : "Oldest First", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("series.sort")
            }

            if let detail {
                Menu {
                    Button {
                        markUnread(nil)
                    } label: {
                        Label("Mark Series as Unread", systemImage: "circle")
                    }
                    .disabled(!detail.hasProgress)
                    .accessibilityIdentifier("series.more.unread")
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .accessibilityIdentifier("series.more")
            }
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
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(detail.displayChapters(newestFirst: newestFirst)) { chapter in
                    ChapterRow(chapter: chapter, seriesHasProgress: detail.hasProgress,
                               open: { open(chapter) },
                               markUnread: { markUnread([chapter]) },
                               markSeriesUnread: { markUnread(nil) })
                }
            }
            .focusSection()
        }
    }

    private func open(_ chapter: Chapter) {
        guard let detail else { return }
        reader = ReaderRoute(series: summary, chapters: detail.chapters, start: chapter)
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
                markError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await load()
        }
    }

    private func load() async {
        do {
            let firstLoad = detail == nil
            detail = try await model.seriesDetail(series.ref)
            errorMessage = nil
            if firstLoad { focus = .primary }
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
    let open: () -> Void
    let markUnread: () -> Void
    let markSeriesUnread: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 24) {
                Image(systemName: icon)
                    .foregroundStyle(chapter.isRead ? Color.secondary : Color.accentColor)
                    .frame(width: 40)
                Text(chapter.title)
                    .lineLimit(1)
                    .foregroundStyle(chapter.isRead ? Color.secondary : Color.primary)
                Spacer()
                Text(chapter.readState.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let date = chapter.updatedAt {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("chapter.\(chapter.id)")
        .accessibilityValue(chapter.readState == .read ? "read" : chapter.readState == .unread ? "unread" : "in progress")
        .contextMenu {
            Button(action: markUnread) {
                Label("Mark as Unread", systemImage: "circle")
            }
            .disabled(chapter.readState == .unread)
            .accessibilityIdentifier("chapter.menu.unread")
            Button(action: markSeriesUnread) {
                Label("Mark Series as Unread", systemImage: "circle.dashed")
            }
            .disabled(!seriesHasProgress)
            .accessibilityIdentifier("chapter.menu.seriesUnread")
        }
    }

    private var icon: String {
        switch chapter.readState {
        case .read: return "checkmark.circle.fill"
        case .inProgress: return "circle.lefthalf.filled"
        case .unread: return "circle"
        }
    }
}
