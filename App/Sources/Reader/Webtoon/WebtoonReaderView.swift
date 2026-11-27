import SwiftUI
import MangaCore

/// Continuous vertical strip reader for webtoons and long-strip manga.
///
/// Pages are stacked in a centered column (`settings.webtoonWidth` of the
/// screen) with no gap: every page's height is a whole number of device
/// pixels worked out from the column width and the page's aspect ratio, so
/// one page's bottom edge is exactly the next one's top edge. Until a page's
/// real size is known it gets an estimated height, and when the size arrives
/// the strip re-lays out around what's on screen so nothing jumps.
///
/// Siri Remote (docs/READER_CONTROLS.md section 10, `ReaderControls`):
/// - Swipe on the touch surface to scroll, with momentum.
/// - Click up or down to move `settings.webtoonScrollStep` of a screen;
///   hold to scroll continuously (it speeds up the longer you hold).
/// - Click left or right to snap to the previous or next page.
/// - Play/Pause starts or stops auto-scroll; holding it opens the reader
///   options (both caught by `ReaderRemoteCatcher` in `ReaderView`). While
///   auto-scroll runs, swiping (or clicking) up/down makes it faster or
///   slower, one named step at a time. The speed is saved for the profile.
/// - A click retries a page that didn't load.
/// - Menu closes what's open, stops auto-scroll, then closes the reader.
///
/// Game controller: either stick scrolls smoothly, X toggles auto-scroll,
/// L1/R1 jump chapters (`GamepadMapping`).
///
/// The next chapter joins the bottom of the strip as you near the end, and
/// the previous one the top as you scroll up, with a divider between them.
/// Only views near the screen exist and far chapters are dropped, so
/// 200-page chapters and long binges stay light on memory.
struct WebtoonReaderView: View {
    let session: ReaderSession

    var body: some View {
        ZStack(alignment: .bottom) {
            WebtoonStripRepresentable(session: session, state: StripState(session: session))
                .pictureAdjustments(session.settings.picture)
                .ignoresSafeArea()
            if session.loadState == .loaded, session.pageCount > 0 {
                VStack(spacing: 12) {
                    if session.isAutoScrolling {
                        AutoScrollBadge(level: session.autoScrollLevel)
                            .transition(.opacity)
                    }
                    // The page number shows with the HUD (a tap).
                    if ReaderHUDPolicy.showsPageNumber(session) {
                        WebtoonIndicator(session: session)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: session.isAutoScrolling)
                .animation(.easeInOut(duration: 0.2), value: session.isHUDVisible)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.webtoon")
    }
}

/// The session values the strip reacts to. Reading them in `body` makes
/// SwiftUI call `updateUIView` whenever one changes.
struct StripState: Equatable {
    var chapterID: String
    var loadState: ReaderSession.LoadState
    var pageCount: Int
    var settings: ReaderSettings
    var menuPresented: Bool
    var jump: PageJump?
    var autoScrolling: Bool
    var autoScrollLevel: Int

    @MainActor
    init(session: ReaderSession) {
        jump = session.pageJump
        chapterID = session.chapter.id
        loadState = session.loadState
        pageCount = session.pageCount
        settings = session.settings
        menuPresented = session.isMenuPresented
        autoScrolling = session.isAutoScrolling
        autoScrollLevel = session.autoScrollLevel
    }
}

private struct WebtoonStripRepresentable: UIViewRepresentable {
    let session: ReaderSession
    let state: StripState

    func makeCoordinator() -> WebtoonStripController {
        WebtoonStripController(session: session)
    }

    func makeUIView(context: Context) -> WebtoonContainerView {
        let controller = context.coordinator
        controller.sync()
        return controller.container
    }

    func updateUIView(_ view: WebtoonContainerView, context: Context) {
        let controller = context.coordinator
        controller.sync()
        if !state.menuPresented {
            // Take focus back when the menu closes.
            // Wait a moment so the menu's buttons are gone first.
            for delay in [0.1, 0.4, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { view.requestFocus() }
            }
        }
    }

    static func dismantleUIView(_ view: WebtoonContainerView, coordinator: WebtoonStripController) {
        coordinator.teardown()
    }
}

/// "Chapter 3 · 12 / 40" at the bottom of the screen.
private struct WebtoonIndicator: View {
    let session: ReaderSession

    var body: some View {
        let text = "\(session.chapter.title) · \(session.currentPage + 1) / \(session.pageCount)"
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
            .padding(.bottom, 24)
            .allowsHitTesting(false)
            .accessibilityIdentifier("reader.webtoon.indicator")
            .accessibilityLabel(text)
    }
}

/// "Auto-scroll · Slow" above the page indicator while it runs.
private struct AutoScrollBadge: View {
    let level: Int

    var body: some View {
        let text = "Auto-scroll · \(WebtoonAutoScroll.label(level))"
        Label(text, systemImage: "play.fill")
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("reader.webtoon.autoScroll")
            .accessibilityLabel(text)
    }
}
