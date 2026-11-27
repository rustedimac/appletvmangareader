import SwiftUI
import MangaCore

/// Hardware keyboard in the readers (iPad keyboards, docs/IOS.md §2):
/// ← / → turn the page (or jump a page in the vertical reader), space
/// goes forward, ↑ / ↓ scroll the vertical reader, Esc closes the options
/// and then the reader.
extension View {
    func readerKeyboardShortcuts(session: ReaderSession?, onClose: @escaping () -> Void) -> some View {
        background {
            if let session {
                ReaderKeyboardShortcuts(session: session, onClose: onClose)
            }
        }
    }
}

private struct ReaderKeyboardShortcuts: View {
    let session: ReaderSession
    let onClose: () -> Void

    var body: some View {
        ZStack {
            key(.leftArrow) { side(.left) }
            key(.rightArrow) { side(.right) }
            key(.space) { side(ReaderTouch.forwardScreenDirection(session.settings.direction)) }
            key(.upArrow) { if session.settings.mode == .webtoon { session.scrollStep(forward: false) } }
            key(.downArrow) { if session.settings.mode == .webtoon { session.scrollStep(forward: true) } }
            key(.escape) {
                if session.isMenuPresented { session.isMenuPresented = false } else { onClose() }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func side(_ direction: ScreenDirection) {
        guard !session.isMenuPresented else { return }
        switch session.settings.mode {
        case .paged: session.turn(direction)
        case .webtoon: session.jumpWebtoonPage(forward: direction == .right)
        }
    }

    private func key(_ key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button("", action: action).keyboardShortcut(key, modifiers: [])
    }
}
