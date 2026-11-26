import SwiftUI
import MangaCore

enum PosterMetrics {
    static let width: CGFloat = 230
    static var height: CGFloat { width * 1.5 }
    static let spacing: CGFloat = 48
    /// How much `.buttonStyle(.card)` scales a focused poster (measured
    /// on tvOS 26: about 1.1).
    static let focusScale: CGFloat = 1.1

    /// How far the title under a poster moves down while the poster has
    /// focus: the half of the scale-up that grows below the cover, plus a
    /// gap, so the lifted cover and its shadow never sit on the title.
    static func focusedTitleDrop(forWidth width: CGFloat) -> CGFloat {
        (width * 1.5 * (focusScale - 1) / 2).rounded(.up) + Space.xs
    }
}

private struct PosterWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = PosterMetrics.width
}

extension EnvironmentValues {
    /// Poster width for `SeriesPoster`. Grids set it from the profile's
    /// poster size (`GridDensity`), and so do shelves.
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
    /// Whether this poster's button has focus (moves the title down).
    @FocusState private var isPosterFocused: Bool

    var body: some View {
        let style = model.posterCaption
        let badges = PosterBadges(series: badgeSeries, caption: style)
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
                    // Take the height two lines need; without it a shelf can
                    // squeeze a long title onto one truncated line.
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("poster.title.\(series.ref.seriesID)")
                if let caption = badges.caption {
                    // The server name shares the caption's line, so a
                    // merged row doesn't get taller.
                    Text(serverLabel == .underTitle ? [caption, serverName].compactMap { $0 }.joined(separator: " · ") : caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("poster.caption.\(series.ref.seriesID)")
                }
                if let read = badges.titleProgress {
                    TitleProgressBar(fraction: read)
                        .padding(.top, 6)
                        .accessibilityElement()
                        .accessibilityLabel("Reading progress")
                        .accessibilityValue("\(Int((read * 100).rounded())) percent")
                        .accessibilityIdentifier("poster.titleProgress.\(series.ref.seriesID)")
                }
                if badges.caption == nil, serverLabel == .underTitle, let serverName {
                    Text(serverName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("poster.server.\(series.ref.seriesID)")
                }
            }
            .frame(width: width, alignment: .leading)
            // The focused cover grows over the space under it; move the
            // title out of its way (like the TV app does).
            .offset(y: isPosterFocused ? PosterMetrics.focusedTitleDrop(forWidth: width) : 0)
            .animation(.easeOut(duration: 0.2), value: isPosterFocused)
        }
        // Grids that fill right to left flip only the layout, not the text.
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { requestCountIfNeeded(style) }
        .onChange(of: style) { _, new in requestCountIfNeeded(new) }
        .onDisappear { model.seriesCounts.cancel(series.ref) }
    }

    /// Kavita listings have no chapter count; fetch it for posters on
    /// screen (see `SeriesCountStore`).
    private func requestCountIfNeeded(_ style: PosterCaption) {
        guard style.needsChapterCount(series), model.seriesCounts.count(for: series.ref) == nil,
              let client = model.client(for: series.ref) else { return }
        model.seriesCounts.request(series.ref, client: client)
    }

    /// The server's name, when this poster should say which server it's from.
    private var serverName: String? {
        guard showsServer, serverLabel != .off else { return nil }
        return model.state.server(series.ref.serverID)?.name
    }

    private var serverLabel: PosterServerLabel { model.posterServerLabel }

    /// The series with any count changed by "Mark as Unread" since the row
    /// loaded. Its page progress is stale then, so badges use the count.
    private var badgeSeries: SeriesSummary {
        let counted = series.withCount(model.seriesCounts.count(for: series.ref))
        guard let override = model.unreadCountOverrides[series.ref] else { return counted }
        var s = counted
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
                .overlay(alignment: .bottomLeading) {
                    if let badge = series.format?.badge {
                        // Above the progress bar.
                        FormatBadge(text: badge).padding(10).padding(.bottom, badges.progress == nil ? 0 : 8)
                    }
                }
                .overlay(alignment: .topTrailing) { corner(badges.corner) }
                .overlay(alignment: .topLeading) {
                    if serverLabel == .onCover, let serverName { ServerTag(name: serverName, maxWidth: width * 0.62) }
                }
                .overlay(alignment: .bottom) {
                    if let progress = badges.progress { ProgressBadge(fraction: progress) }
                }
        }
        .buttonStyle(.card)
        .focused($isPosterFocused)
        // VoiceOver hears the server wherever the poster shows it.
        .accessibilityLabel(serverName.map { "\(series.title), \($0)" } ?? series.title)
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
            UnreadBadge(count: n)
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

/// The unread-chapter count in a cover's top-right corner. White bold
/// digits on a near-opaque dark capsule with a light rim: the plate keeps
/// the digits readable on white covers (about 13:1), and the rim keeps the
/// plate visible on dark ones. A translucent tint fill washed out on light
/// covers.
private struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption.bold())
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(minWidth: 52)
            .background(Color.black.opacity(0.82), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .padding(10)
    }
}

/// The `.onCover` server label: the server's name in a small dark tag in
/// the cover's top-left corner, clear of the unread count on the right.
private struct ServerTag: View {
    let name: String
    let maxWidth: CGFloat

    var body: some View {
        Text(name)
            .font(.caption2.bold())
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.small))
            .foregroundStyle(.white)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .accessibilityIdentifier("poster.serverTag")
            .accessibilityLabel(name)
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

/// The `.progress` caption: a thin bar under the title, full width of the
/// poster, empty for unread series.
private struct TitleProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.35))
                Capsule().fill(.tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// A titled horizontal row of posters (Home rows, search results).
struct SeriesShelf: View {
    @Environment(AppModel.self) private var model
    let title: String
    let series: [SeriesSummary]
    var identifier: String? = nil
    var showsServer = false
    /// When set, posters offer "Remove from Continue Reading".
    var onRemove: ((SeriesSummary) -> Void)? = nil

    var body: some View {
        // Shelves follow the profile's poster size too, and change as soon
        // as it's picked (Customize Home or a library's Sort & View).
        let density = model.gridDensity
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("shelf.\(identifier ?? title)")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: CGFloat(density.spacing)) {
                    ForEach(series) { item in
                        SeriesPoster(series: item, showsServer: showsServer,
                                     onRemoveFromContinueReading: onRemove == nil ? nil : { onRemove?(item) })
                    }
                }
                // Lazy stacks can keep cells at their old size; rebuild.
                .id(density)
                .environment(\.posterWidth, CGFloat(density.posterWidth))
                .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
        // Lets UI tests find a poster within one shelf: the same series id
        // can be on two servers' shelves.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelfRow.\(identifier ?? title)")
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
        // Lazy grids can keep cells at their old size; rebuild on a new one.
        .id(density)
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
        // Try Again is reachable from anywhere in the rows above or below.
        .centeredFocusRow()
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
