import SwiftUI
import UIKit
import MangaCore

/// Full-screen reader for reflowable books (EPUB, plain text). `ReaderView`
/// opens this instead of the image readers when the chapter's format is
/// text.
///
/// Siri Remote (`ReaderControls.bookRemote`): left/right (click or swipe)
/// turns the page. Holding Play/Pause opens the settings drawer, as in the
/// image readers (`ReaderRemoteCatcher`). Menu closes the drawer, or saves
/// progress and closes the book.
struct BookReaderView: View {
    let series: SeriesSummary
    let chapters: [Chapter]
    let start: Chapter
    /// Overrides the server client (UI tests and previews).
    var server: MangaServer? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: BookReaderSession?
    @State private var unsupported = false

    var body: some View {
        ZStack {
            Color(uiColor: (session?.settings.theme ?? model.bookSettings.theme).backgroundColor)
                .ignoresSafeArea()
            if let session {
                BookReaderContent(session: session)
            } else if unsupported {
                VStack(spacing: 20) {
                    Text("This server can't open books yet").font(.title3)
                    Text("\(start.format?.displayName ?? "This format") reading isn't available for this source.")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("book.unsupported")
            } else {
                ProgressView()
            }
        }
        .ignoresSafeArea()
        .background {
            if let session {
                ReaderRemoteCatcher(onPlayPause: {
                    // Nothing plays in a book; a press only closes the drawer.
                    if session.isMenuPresented { session.isMenuPresented = false }
                }, onPlayPauseHold: { session.isMenuPresented.toggle() })
            }
        }
        .onExitCommand {
            if let session, session.isMenuPresented {
                session.isMenuPresented = false
            } else {
                session?.close()
                dismiss()
            }
        }
        .task {
            guard session == nil, !unsupported else { return }
            guard let books = (server ?? model.client(for: series.ref)) as? BookProviding else {
                unsupported = true
                return
            }
            let s = BookReaderSession(model: model, server: books, series: series, chapters: chapters, start: start)
            session = s
            await s.start()
        }
        .onDisappear { session?.close() }
        // Home button or screen saver: save before tvOS may suspend the app.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session?.flushProgress() }
        }
    }
}

private struct BookReaderContent: View {
    let session: BookReaderSession
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            BookReaderSurface(session: session)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onMoveCommand(perform: handleMove)
                .onAppear { focused = true }
                .onChange(of: session.isMenuPresented) { _, presented in
                    if !presented { focused = true }
                }
                // Keep focus inside the drawer while it's open.
                .disabled(session.isMenuPresented)
            if session.isMenuPresented {
                BookReaderMenu(session: session)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isMenuPresented)
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: Task { await session.turn(forward: false) }
        case .right: Task { await session.turn(forward: true) }
        default: break
        }
    }
}

/// The page, the position line, and loading and edge states.
private struct BookReaderSurface: View {
    let session: BookReaderSession

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: session.settings.theme.backgroundColor)
                if let edge = session.edge {
                    BookEdgeCard(session: session, edge: edge)
                } else if let layout = session.currentLayout, session.loadState == .loaded {
                    let page = min(session.cursor.page, max(0, layout.pageCount - 1))
                    BookPageCanvas(layout: layout, page: page, background: session.settings.theme.backgroundColor)
                        .accessibilityElement()
                        .accessibilityIdentifier("book.page")
                        .accessibilityLabel(layout.text(onPage: page))
                        .accessibilityValue("\(layout.section + 1).\(page + 1)")
                }
                VStack {
                    Spacer()
                    if session.loadState == .loaded {
                        BookPositionLine(session: session)
                    }
                }
                .padding(.bottom, 44)
                BookLoadStateView(session: session)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { session.setViewport(geo.size) }
            .onChange(of: geo.size) { _, size in session.setViewport(size) }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("book.reader")
    }
}

/// Draws one screen page with the same TextKit objects that paginated it.
private struct BookPageCanvas: UIViewRepresentable {
    let layout: BookSectionLayout
    let page: Int
    let background: UIColor

    func makeUIView(context: Context) -> BookPageCanvasView {
        let view = BookPageCanvasView()
        view.isUserInteractionEnabled = false
        view.contentMode = .redraw
        return view
    }

    func updateUIView(_ view: BookPageCanvasView, context: Context) {
        view.backgroundColor = background
        if view.layout !== layout || view.page != page {
            view.layout = layout
            view.page = page
            view.setNeedsDisplay()
        }
    }
}

final class BookPageCanvasView: UIView {
    var layout: BookSectionLayout?
    var page = 0

    override func draw(_ rect: CGRect) {
        layout?.draw(page: page)
    }
}

private struct BookPositionLine: View {
    let session: BookReaderSession

    var body: some View {
        HStack(spacing: 16) {
            let title = session.currentTOCEntry?.title ?? session.chapter.title
            if !title.isEmpty {
                Text(title).lineLimit(1)
                Text("·")
            }
            Text(label).accessibilityIdentifier("book.position")
        }
        .font(.caption)
        .foregroundStyle(Color(uiColor: session.settings.theme.secondaryColor))
        .frame(maxWidth: 1400)
    }

    private var label: String {
        let count = session.pageCount
        guard count > 0 else { return "\(session.percent)%" }
        return "Page \(min(session.cursor.page, count - 1) + 1) of \(count) · \(session.percent)%"
    }
}

private struct BookEdgeCard: View {
    let session: BookReaderSession
    let edge: ChapterEdge

    var body: some View {
        let other = session.chapter(across: edge)
        VStack(spacing: 24) {
            Image(systemName: edge == .end ? "book.closed" : "arrow.uturn.backward")
                .font(.system(size: 80))
            Text(edge == .end ? (other == nil ? "The End" : "End of \(session.chapter.title)")
                              : "Start of \(session.chapter.title)")
                .font(.title2.bold())
            if let other {
                Text("\(edge == .end ? "Next" : "Previous"): \(other.title)")
                Text(edge == .end ? "Press right to continue" : "Press left to go back")
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color(uiColor: session.settings.theme.textColor))
        .padding(80)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("book.edge")
    }
}

private struct BookLoadStateView: View {
    let session: BookReaderSession

    var body: some View {
        switch session.loadState {
        case .loading:
            ProgressView().accessibilityIdentifier("book.loading")
        case .failed(let message):
            VStack(spacing: 24) {
                Text("Couldn't open \(session.chapter.title)").font(.title3)
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { Task { await session.retry() } }
            }
            .padding(60)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("book.error")
        case .loaded:
            EmptyView()
        }
    }
}
