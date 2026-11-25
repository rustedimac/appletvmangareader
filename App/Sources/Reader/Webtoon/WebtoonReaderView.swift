import SwiftUI
import MangaCore

/// Continuous vertical strip reader. Placeholder until workstream F lands;
/// it owns this folder. Drive `session.reportVisiblePage(_:)` and
/// `session.reportSize(_:forPage:)`; open the menu with
/// `session.isMenuPresented = true`.
struct WebtoonReaderView: View {
    let session: ReaderSession

    var body: some View {
        VStack(spacing: 24) {
            Text("Vertical scroll is coming soon.").font(.title3)
            Text("Switch to Paged in the reader menu.").foregroundStyle(.secondary)
        }
        .focusable()
        .onPlayPauseCommand { session.isMenuPresented = true }
        .onMoveCommand { if $0 == .down { session.isMenuPresented = true } }
        .accessibilityIdentifier("reader.webtoon")
    }
}
