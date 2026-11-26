import SwiftUI
import MangaCore

/// Settings > "Remote and Controller": every button in the readers and the
/// chapter list, from `ReaderControls`, so the screen always matches what
/// the readers do. Rows are focusable only so the form can scroll.
struct ControlsHelpView: View {
    var body: some View {
        Form {
            section("Page Reader", ReaderControls.remote(for: .paged), id: "paged")
            section("Vertical Reader", ReaderControls.remote(for: .webtoon), id: "webtoon")
            section("Book Reader (EPUB and Text)", ReaderControls.bookRemote, id: "book")
            section("Game Controller", ReaderControls.gamepad, id: "gamepad",
                    footer: "Works in every reader. A, B and the d-pad also work everywhere else in the app.")
            section("Chapter List", ReaderControls.chapterList, id: "chapters",
                    footer: "In the Simulator, hold Return (or the remote's click) for a long press.")
        }
        .settingsPage("Remote and Controller", systemImage: "appletvremote.gen4")
    }

    private func section(_ title: String, _ entries: [ReaderControls.Entry], id: String,
                         footer: String? = nil) -> some View {
        Section {
            ForEach(entries) { entry in
                ControlRow(entry: entry)
                    .accessibilityIdentifier("controls.\(id).\(entry.input)")
            }
        } header: {
            SettingsHeader(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }
}

private struct ControlRow: View {
    let entry: ReaderControls.Entry

    var body: some View {
        // A button with no action: focusable like other rows, does nothing.
        Button {} label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(entry.input)
                Text(entry.action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
