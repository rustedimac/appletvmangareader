import SwiftUI
import MangaCore

enum PosterMetrics {
    static let width: CGFloat = 230
    static var height: CGFloat { width * 1.5 }
    static let spacing: CGFloat = 48
}

private struct PosterWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = PosterMetrics.width
}

extension EnvironmentValues {
    /// Poster width for `SeriesPoster`. Grids set it from the profile's
    /// poster size (`GridDensity`); shelves use the default.
    var posterWidth: CGFloat {
        get { self[PosterWidthKey.self] }
        set { self[PosterWidthKey.self] = newValue }
    }
}

/// A focusable poster that opens series detail. Lifts on focus (card
/// button style) and shows `PosterBadges`: unread chapters or a check in
/// the corner, a progress bar, and the series' size under the title.
/// Long-press offers Mark Series as Unread.
struct SeriesPoster: View {
    @Environment(AppModel.self) private var model
    @Environment(\.posterWidth) private var width
    let series: SeriesSummary
    var showsServer = false
    /// Adds "Remove from Continue Reading" to the long-press menu.
    var onRemoveFromContinueReading: (() -> Void)? = nil
    /// Lets a grid move focus to this poster (A–Z jump).
    var focus: FocusState<SeriesRef?>.Binding? = nil
    @State private var markError: String?

    var body: some View {
        let badges = PosterBadges(series: badgeSeries)
        VStack(alignment: .leading, spacing: 14) {
            link(badges)
                .alert("Couldn't mark as unread", isPresented: Binding(get: { markError != nil }, set: { if !$0 { markError = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(markError ?? "")
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(series.title)
                    .font(width < PosterMetrics.width ? .caption2 : .caption)
                    .lineLimit(2)
                if let caption = badges.caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("poster.caption.\(series.ref.seriesID)")
                }
                if showsServer, let server = model.state.server(series.ref.serverID) {
                    Text(server.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        // Grids that fill right to left flip only the layout, not the text.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// The series with any count changed by "Mark as Unread" since the row
    /// loaded. Its page progress is stale then, so badges use the count.
    private var badgeSeries: SeriesSummary {
        guard let override = model.unreadCountOverrides[series.ref] else { return series }
        var s = series
        s.unreadCount = override
        s.pagesRead = nil
        return s
    }

    @ViewBuilder
    private func link(_ badges: PosterBadges) -> some View {
        let base = NavigationLink(value: series) {
            PosterImage(url: series.coverURL, server: model.client(for: series.ref), title: series.title)
                .frame(width: width, height: width * 1.5)
                .clipped()
                .overlay(alignment: .topTrailing) { corner(badges.corner) }
                .overlay(alignment: .bottom) {
                    if let progress = badges.progress { ProgressBadge(fraction: progress) }
                }
        }
        .buttonStyle(.card)
        .accessibilityLabel(series.title)
        .accessibilityValue(badges.accessibilityValue)
        .accessibilityIdentifier("poster.\(series.ref.seriesID)")
        .contextMenu {
            if let onRemoveFromContinueReading {
                Button(role: .destructive, action: onRemoveFromContinueReading) {
                    Label("Remove from Continue Reading", systemImage: "minus.circle")
                }
                .accessibilityIdentifier("poster.menu.removeFromContinueReading")
            }
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
        if let focus {
            base.focused(focus, equals: series.ref)
        } else {
            base
        }
    }

    @ViewBuilder
    private func corner(_ corner: PosterBadges.Corner) -> some View {
        switch corner {
        case .unread(let n):
            Text("\(n)")
                .font(.caption2.bold())
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
                .padding(10)
        case .finished:
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .padding(8)
                .background(Color.green.opacity(0.9), in: Circle())
                .foregroundStyle(.white)
                .padding(10)
        case .none:
            EmptyView()
        }
    }
}

/// A thin read-progress bar along the bottom of a cover.
private struct ProgressBadge: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.55))
                Rectangle().fill(.tint).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 8)
    }
}

/// A titled horizontal row of posters (Home rows, search results).
struct SeriesShelf: View {
    let title: String
    let series: [SeriesSummary]
    var identifier: String? = nil
    var showsServer = false
    /// When set, posters offer "Remove from Continue Reading".
    var onRemove: ((SeriesSummary) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("shelf.\(identifier ?? title)")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: PosterMetrics.spacing) {
                    ForEach(series) { item in
                        SeriesPoster(series: item, showsServer: showsServer,
                                     onRemoveFromContinueReading: onRemove == nil ? nil : { onRemove?(item) })
                    }
                }
                .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// A vertical poster grid sized by the profile's poster size. `onShow`
/// fires as each item appears, for infinite paging. Each poster has its
/// `SeriesRef` as scroll id, so a `ScrollViewReader` can jump to it.
struct SeriesGrid: View {
    @Environment(AppModel.self) private var model
    let series: [SeriesSummary]
    var showsServer = false
    /// Fill rows right to left (manga order).
    var rightToLeft = false
    var focus: FocusState<SeriesRef?>.Binding? = nil
    var onShow: (Int) -> Void = { _ in }

    var body: some View {
        let density = model.gridDensity
        let width = CGFloat(density.posterWidth)
        let columns = [GridItem(.adaptive(minimum: width, maximum: width + 20),
                                spacing: CGFloat(density.spacing), alignment: .top)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: CGFloat(density.spacing) + 8) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                SeriesPoster(series: item, showsServer: showsServer, focus: focus)
                    .id(item.ref)
                    .onAppear { onShow(index) }
            }
        }
        .environment(\.posterWidth, width)
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
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
