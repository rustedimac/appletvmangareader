import SwiftUI
import MangaCore

/// In-reader settings menu, shown over the page while
/// `session.isMenuPresented` is true. Placeholder until workstream G lands;
/// it owns this folder. Apply changes with `session.updateSettings(_:)`.
/// The Menu button already closes it (ReaderView handles that).
struct ReaderMenu: View {
    let session: ReaderSession

    var body: some View {
        VStack {
            HStack(spacing: 40) {
                ForEach(ReadingMode.allCases) { mode in
                    Button(mode.title) {
                        var s = session.settings
                        s.mode = mode
                        session.updateSettings(s)
                    }
                }
                Button("Close") { session.isMenuPresented = false }
            }
            .padding(40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .padding(.top, 60)
        .accessibilityIdentifier("reader.menu")
    }
}
