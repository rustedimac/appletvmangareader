import SwiftUI
import MangaCore

enum PosterMetrics {
    static let width: CGFloat = 230
    static var height: CGFloat { width * 1.5 }
    static let spacing: CGFloat = 48
}

/// A focusable poster that opens series detail. Lifts on focus (card
/// button style) and shows the unread count. Long-press offers Mark Series
/// as Unread.
struct SeriesPoster: View {
    @Environment(AppModel.self) private var model
    let series: SeriesSummary
    var showsServer = false
    @State private var markError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: series) {
                PosterImage(url: series.coverURL, server: model.client(for: series.ref), title: series.title)
                    .frame(width: PosterMetrics.width, height: PosterMetrics.height)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        if let badge = series.format?.badge {
                            FormatBadge(text: badge).padding(10)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let unread = model.unreadCount(for: series), unread > 0 {
                            Text("\(unread)")
                                .font(.caption2.bold())
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.tint, in: Capsule())
                                .foregroundStyle(.white)
                                .padding(10)
                        }
                    }
            }
            .buttonStyle(.card)
            .accessibilityLabel(series.title)
            .accessibilityIdentifier("poster.\(series.ref.seriesID)")
            .contextMenu {
                Button {
                    Task {
                        do {
                            try await model.markSeriesUnread(series.ref)
                        } catch {
                            markError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                } label: {
                    Label("Mark Series as Unread", systemImage: "circle")
                }
                .accessibilityIdentifier("poster.menu.seriesUnread")
            }
            .alert("Couldn't mark as unread", isPresented: Binding(get: { markError != nil }, set: { if !$0 { markError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(markError ?? "")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(series.title)
                    .font(.caption)
                    .lineLimit(2)
                if showsServer, let server = model.state.server(series.ref.serverID) {
                    Text(server.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: PosterMetrics.width, alignment: .leading)
        }
    }
}

/// A titled horizontal row of posters (Home rows, search results).
struct SeriesShelf: View {
    let title: String
    let series: [SeriesSummary]
    var identifier: String? = nil
    var showsServer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("shelf.\(identifier ?? title)")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: PosterMetrics.spacing) {
                    ForEach(series) { SeriesPoster(series: $0, showsServer: showsServer) }
                }
                .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// A vertical poster grid. `onShow` fires as each item appears, for
/// infinite paging.
struct SeriesGrid: View {
    let series: [SeriesSummary]
    var showsServer = false
    var onShow: (Int) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: PosterMetrics.width, maximum: PosterMetrics.width + 20),
                                    spacing: PosterMetrics.spacing, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                SeriesPoster(series: item, showsServer: showsServer)
                    .onAppear { onShow(index) }
            }
        }
        .padding(.vertical, 30)
        .focusSection()
    }
}

/// Message shown in place of content (empty, error, nothing set up).
struct BrowseMessage: View {
    let title: String
    var message: String = ""
    var systemImage: String = "books.vertical"
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(title).font(.title3)
            if !message.isEmpty {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }
            if let retry {
                Button("Try Again", action: retry)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Registers series detail as a destination of the enclosing
    /// NavigationStack.
    func seriesNavigation() -> some View {
        navigationDestination(for: SeriesSummary.self) { SeriesDetailView(series: $0) }
    }
}

/// A small "PDF" / "EPUB" tag, so non-comic content stands out in a grid
/// of manga. Image content has no badge.
struct FormatBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
            .accessibilityIdentifier("format.badge")
            .accessibilityLabel(text)
    }
}
