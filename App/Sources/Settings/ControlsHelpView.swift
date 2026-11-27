import SwiftUI
import MangaCore

/// Settings > "Remote and Controller": what every button does, from
/// `ReaderControls`, so the screen always matches the readers. The Paged
/// and Vertical tabs also replay the controls tutorial.
///
/// A legend, not a list of rows: the only things that take focus are the
/// tabs that pick which reader (or the game controller, or the chapter
/// list) the legend shows, and the tutorial button. The entries themselves are plain text, so
/// nothing on the page looks like a button that does nothing. Tabs without
/// a tutorial must fit under the tab bar without scrolling (nothing below
/// the tabs takes focus); `DesignLayoutUITests.testControlsPageNeverClips`
/// checks every tab.
struct ControlsHelpView: View {
    @State private var tab: ControlsTab = .paged
    @FocusState private var focus: String?
    /// The controls tutorial being replayed (`ReaderTutorialView`).
    @State private var tutorial: ReadingMode?

    var body: some View {
        // A scroll view, like Customize Home: on a 1080p TV the Paged legend
        // plus the tutorial row is taller than the space under the tab bar,
        // and a plain VStack that overflows gets centered, pushing the tabs
        // under the tab bar and the last lines off the bottom with no way
        // to reach them. The tutorial button is the last thing on the page,
        // with its caption beside it, so focusing it scrolls everything in.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionTabBar(tabs: ControlsTab.allCases, selection: $tab, title: \.title,
                              identifier: { "controls.tab.\($0.rawValue)" }, focus: $focus,
                              focusKey: { "tab.\($0.rawValue)" }, trackIdentifier: "controls.tabs")
                    .padding(.bottom, Space.xs)
                if let footnote = tab.footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("controls.footnote")
                }
                ControlsLegend(entries: tab.entries, id: tab.rawValue)
                if let mode = tab.tutorialMode {
                    // Replays the controls tutorial on the bundled sample.
                    // The caption sits beside the button, so the button is
                    // the page's last row and focusing it shows the caption.
                    HStack(alignment: .center, spacing: Space.l) {
                        Button {
                            tutorial = mode
                        } label: {
                            Label("Learn the Controls", systemImage: "hand.point.up.left")
                                .lineLimit(1)
                        }
                        .fixedSize()
                        .focused($focus, equals: "tutorial")
                        .accessibilityIdentifier("controls.tutorial.\(mode.rawValue)")
                        Text("Try each button on a short sample comic. \(ReaderTutorial.shortCredit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("controls.tutorial.caption")
                    }
                    .padding(.top, Space.s)
                }
            }
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultFocus($focus, "tab.\(ControlsTab.paged.rawValue)")
        .settingsPage("Remote and Controller", systemImage: "appletvremote.gen4")
        .fullScreenCover(item: $tutorial) { mode in
            ReaderTutorialView(mode: mode)
        }
    }
}

enum ControlsTab: String, CaseIterable, Identifiable {
    case paged
    case webtoon
    case book
    case gamepad
    case chapters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paged: return "Paged"
        case .webtoon: return "Vertical"
        case .book: return "Books"
        case .gamepad: return "Controller"
        case .chapters: return "Chapter List"
        }
    }

    var entries: [ReaderControls.Entry] {
        switch self {
        case .paged: return ReaderControls.remote(for: .paged)
        case .webtoon: return ReaderControls.remote(for: .webtoon)
        case .book: return ReaderControls.bookRemote
        case .gamepad: return ReaderControls.gamepad
        case .chapters: return ReaderControls.chapterList
        }
    }

    /// The tutorial this tab offers (the two image readers).
    var tutorialMode: ReadingMode? {
        switch self {
        case .paged: return .paged
        case .webtoon: return .webtoon
        case .book, .gamepad, .chapters: return nil
        }
    }

    var footnote: String? {
        switch self {
        case .paged: return "Siri Remote in the page reader."
        case .webtoon: return "Siri Remote in the vertical (webtoon) reader."
        case .book: return "Siri Remote in the EPUB and text reader."
        case .gamepad: return "Works in every reader. A, B and the d-pad also work everywhere else in the app."
        case .chapters: return "On a series' chapter list. In the Simulator, hold Return (or the remote's click) for a long press."
        }
    }
}

/// Two columns of plain text: the button on the left, what it does on the
/// right. Not focusable. Each entry reads as one accessibility element,
/// `controls.<id>.<input>`.
struct ControlsLegend: View {
    let entries: [ReaderControls.Entry]
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                    Text(entry.input)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Self.inputColumn, alignment: .leading)
                    Text(entry.action)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("controls.\(id).\(entry.input)")
            }
        }
    }

    /// Wide enough for "Swipe or click left or right" on one line.
    static let inputColumn: CGFloat = 380
}
