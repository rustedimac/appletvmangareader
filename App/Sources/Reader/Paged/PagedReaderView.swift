import SwiftUI
import MangaCore

/// Two-page spread reader. Full implementation follows in the next PR.
struct PagedReaderView: View {
    let session: ReaderSession

    var body: some View {
        Text(session.visiblePages.map { "\($0 + 1)" }.joined(separator: " – "))
            .font(.largeTitle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .left: session.turn(.left)
                case .right: session.turn(.right)
                case .down: session.isMenuPresented = true
                default: break
                }
            }
            .onPlayPauseCommand { session.isMenuPresented = true }
            .accessibilityIdentifier("reader.paged")
    }
}
