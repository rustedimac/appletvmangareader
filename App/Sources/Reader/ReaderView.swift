import SwiftUI
import MangaCore

/// Full-screen reader. Present it from series detail:
///
///     .fullScreenCover(item: $reading) { r in
///         ReaderView(series: r.series, chapters: r.chapters, start: r.chapter)
///     }
///
/// It switches on `settings.mode` between the paged and webtoon readers and
/// overlays the in-reader menu. The Menu button closes the menu if it is
/// open, otherwise it saves progress and closes the reader.
struct ReaderView: View {
    let series: SeriesSummary
    let chapters: [Chapter]
    let start: Chapter
    /// Page to open at. Nil resumes the chapter's saved progress.
    var startPage: Int? = nil
    /// Overrides the server client (UI tests and previews).
    var server: MangaServer? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: ReaderSession?

    var body: some View {
        ZStack {
            (session?.settings.background.color ?? .black).ignoresSafeArea()
            if let session {
                ReaderContent(session: session)
            } else {
                ProgressView()
            }
        }
        .ignoresSafeArea()
        .onExitCommand {
            if let session, session.isMenuPresented {
                session.isMenuPresented = false
            } else {
                session?.close()
                dismiss()
            }
        }
        .task {
            guard session == nil else { return }
            guard let client = server ?? model.client(for: series.ref) else { return }
            let s = ReaderSession(model: model, server: client, series: series, chapters: chapters,
                                  start: start, startPage: startPage)
            session = s
            await s.start()
        }
        .onDisappear { session?.close() }
    }
}

private struct ReaderContent: View {
    let session: ReaderSession

    var body: some View {
        ZStack {
            switch session.settings.mode {
            case .paged:
                PagedReaderView(session: session)
            case .webtoon:
                WebtoonReaderView(session: session)
            }
            ReaderLoadStateView(session: session)
            if session.isMenuPresented {
                ReaderMenu(session: session)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isMenuPresented)
    }
}

/// Spinner while a chapter loads, and an error with Retry if it fails.
struct ReaderLoadStateView: View {
    let session: ReaderSession

    var body: some View {
        switch session.loadState {
        case .loading:
            ProgressView()
                .accessibilityIdentifier("reader.loading")
        case .failed(let message):
            VStack(spacing: 24) {
                Text("Couldn't load \(session.chapter.title)").font(.title3)
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { Task { await session.retry() } }
            }
            .padding(60)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("reader.error")
        case .loaded:
            EmptyView()
        }
    }
}

extension ReaderBackground {
    var color: Color {
        switch self {
        case .black: return .black
        case .gray: return Color(white: 0.2)
        case .white: return .white
        }
    }
}
