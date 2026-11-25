import SwiftUI
import MangaCore

/// The page-turner reader. Shows one spread at a time: two pages joined edge
/// to edge at a common height, or one page alone (cover, wide spread, or
/// single-page layout).
///
/// Siri Remote: left/right (click or swipe) turns the page, following the
/// reading direction. Swipe down or Play/Pause opens the reader menu. Going
/// past the first or last spread shows a chapter transition card; pressing
/// again opens the previous or next chapter.
struct PagedReaderView: View {
    let session: ReaderSession

    @State private var loader: PageImageLoader?
    @FocusState private var focused: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let edge = session.edge {
                    ChapterTransitionCard(session: session, edge: edge)
                } else if let spread = session.currentSpread, let loader {
                    SpreadView(session: session, spread: spread, loader: loader,
                               container: geo.size, scale: displayScale)
                        .id(spread)
                }
                if session.loadState == .loaded, session.pageCount > 0 {
                    PageIndicator(session: session)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.paged")
        .onMoveCommand(perform: handleMove)
        // Select on a failed page retries it in place.
        .onTapGesture { session.retryVisibleFailedPages() }
        .onPlayPauseCommand { session.isMenuPresented = true }
        .onAppear {
            if loader == nil { loader = PageImageLoader(server: session.server) }
            focused = true
        }
        .onChange(of: session.isMenuPresented) { _, presented in
            if !presented { focused = true }
        }
        .task(id: PreloadKey(chapterID: session.chapter.id, spread: session.currentSpread,
                             count: session.pageCount, loaded: session.loadState == .loaded)) {
            preload()
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: session.turn(.left)
        case .right: session.turn(.right)
        case .down: session.isMenuPresented = true
        default: break
        }
    }

    /// Loads ±2 spreads around the current one, nearest first, and records
    /// sizes as they arrive so later spreads pair correctly before they are
    /// shown.
    private func preload() {
        guard let loader, session.loadState == .loaded else { return }
        let indices = session.navigator.pagesToPreload(radius: 2)
        let urls = indices.compactMap { session.page($0)?.url }
        let byURL = Dictionary(indices.compactMap { i in session.page(i).map { ($0.url, i) } },
                               uniquingKeysWith: { a, _ in a })
        let chapterID = session.chapter.id
        loader.preload(urls) { url, page in
            guard session.chapter.id == chapterID, let index = byURL[url] else { return }
            session.reportSize(page.pixelSize, forPage: index)
        }
    }

    private struct PreloadKey: Hashable {
        var chapterID: String
        var spread: Spread?
        var count: Int
        var loaded: Bool
    }
}

/// One spread, laid out with `SpreadGeometry` so both pages share a height
/// and touch with no seam.
private struct SpreadView: View {
    let session: ReaderSession
    let spread: Spread
    let loader: PageImageLoader
    let container: CGSize
    let scale: CGFloat

    var body: some View {
        let order = spread.screenOrder(session.settings.direction)
        let frames = SpreadGeometry.frames(for: order.map { session.size(ofPage: $0) },
                                           in: Double(container.width), Double(container.height),
                                           scale: Double(scale))
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(order.count, frames.count), id: \.self) { i in
                let index = order[i]
                let frame = frames[i]
                PageImageView(session: session, index: index, loader: loader)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.x, y: frame.y)
            }
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
    }
}

/// A single page image. Drawn to exactly the frame it's given (no aspect
/// fit), because the frame already has the page's aspect ratio; this keeps
/// the two halves of a spread flush.
private struct PageImageView: View {
    let session: ReaderSession
    let index: Int
    let loader: PageImageLoader

    @State private var loaded: LoadedPage?

    private var failure: String? { loaded == nil ? session.pageFailures[index] : nil }

    /// Label, value ("loaded", "failed", "loading") and hint for VoiceOver and UI tests.
    private var accessibilityText: (label: String, value: String, hint: String) {
        if loaded != nil { return ("Page \(index + 1)", "loaded", "") }
        if failure != nil { return ("Page \(index + 1) didn't load", "failed", "Press Select to retry") }
        return ("Page \(index + 1)", "loading", "")
    }

    var body: some View {
        ZStack {
            if let loaded {
                Image(uiImage: loaded.image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else if let failure {
                PageFailureCard(page: index + 1, message: failure)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText.label)
        .accessibilityValue(accessibilityText.value)
        .accessibilityHint(accessibilityText.hint)
        .accessibilityIdentifier("reader.page.\(index)")
        .task(id: LoadKey(url: session.page(index)?.url, retry: session.pageRetryTokens[index] ?? 0)) { await load() }
    }

    private struct LoadKey: Hashable {
        var url: URL?
        var retry: Int
    }

    private func load() async {
        guard let url = session.page(index)?.url else { return }
        if let hit = loader.cached(url) {
            loaded = hit
            session.reportPageLoaded(index)
            session.reportSize(hit.pixelSize, forPage: index)
            return
        }
        guard loaded == nil else { return }
        do {
            let page = try await loader.load(url)
            loaded = page
            session.reportPageLoaded(index)
            session.reportSize(page.pixelSize, forPage: index)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            session.reportPageFailure(PageLoadFailure.message(for: error), forPage: index)
        }
    }
}

/// Shown in place of a page that didn't load after automatic retries. The
/// reader keeps focus (left/right still turn pages), so the Retry pill is
/// drawn as the focused control and Select presses it.
struct PageFailureCard: View {
    let page: Int
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Page \(page) didn't load")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text("Retry")
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 36)
                .padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            Text("Press Select to retry")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .minimumScaleFactor(0.6)
        .padding(32)
        .background(Color(white: 0.12).opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
        .padding(16)
        .frame(maxWidth: 640)
    }
}

/// Small "12–13 / 40" indicator at the bottom of the screen.
private struct PageIndicator: View {
    let session: ReaderSession

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 24)
                .accessibilityIdentifier("reader.pageIndicator")
                .accessibilityLabel(text)
        }
    }

    private var text: String {
        let total = session.pageCount
        if let edge = session.edge {
            return edge == .end ? "End of chapter" : "Start of chapter"
        }
        let pages = session.visiblePages.map { $0 + 1 }
        guard let first = pages.first else { return "" }
        if let last = pages.last, last != first { return "\(first)–\(last) / \(total)" }
        return "\(first) / \(total)"
    }
}

/// Shown between chapters. Names where the next press goes, Mihon style.
struct ChapterTransitionCard: View {
    let session: ReaderSession
    let edge: ChapterEdge

    var body: some View {
        let other = session.chapter(across: edge)
        let forwardKey = session.settings.direction == .rightToLeft ? "left" : "right"
        let backKey = session.settings.direction == .rightToLeft ? "right" : "left"
        VStack(spacing: 28) {
            Text(edge == .end ? "Finished" : "Current")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(session.chapter.title)
                .font(.title2)
            Divider().frame(width: 400)
            if let other {
                Text(edge == .end ? "Next" : "Previous")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(other.title)
                    .font(.title2)
                    .accessibilityIdentifier("reader.transition.target")
                Text("Press \(edge == .end ? forwardKey : backKey) again to continue")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(edge == .end ? "No more chapters" : "This is the first chapter")
                    .font(.title3)
                    .accessibilityIdentifier("reader.transition.none")
                Text("Press Menu to close the reader")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(80)
        .foregroundStyle(.white)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 32))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.transition")
    }
}
