import Foundation

/// The reader's button map, in one place, so the Settings "Remote and
/// Controller" screen, the first-use hint and docs/CONTROLS.md all say the
/// same thing as the readers do.
///
/// The scheme follows tvOS's own media apps: a click (Select) brings up the
/// controls, Play/Pause plays, and Menu goes back. In every reader holding
/// Select opens the reader options; a click does too, except in the page
/// reader, where a click zooms. Play/Pause opens them in the page and book
/// readers; in the vertical reader it starts and stops auto-scroll. The
/// scheme is under review in docs/READER_CONTROLS.md.
public enum ReaderControls {
    public struct Entry: Hashable, Sendable, Identifiable {
        /// "Click", "Play/Pause", "Swipe left or right".
        public var input: String
        /// What it does.
        public var action: String
        public var id: String { input }

        public init(_ input: String, _ action: String) {
            self.input = input
            self.action = action
        }
    }

    /// Siri Remote controls for a reading mode.
    public static func remote(for mode: ReadingMode) -> [Entry] {
        switch mode {
        case .paged:
            return [
                Entry("Hold Select", "Reader options"),
                Entry("Play/Pause", "Reader options"),
                Entry("Swipe or click down", "Reader options (pans down first when zoomed)"),
                Entry("Click", "Zoom in or out (retries a page that didn't load)"),
                Entry("Swipe or click left or right", "Turn the page (follows the reading direction); pans first when zoomed"),
                Entry("Swipe or click up", "Bookmark the page, or remove the bookmark (pans up first when zoomed)"),
                Entry("Menu (Back)", "Zoom out, close the options, then close the reader"),
            ]
        case .webtoon:
            return [
                Entry("Click or hold Select", "Reader options (a click first stops auto-scroll)"),
                Entry("Play/Pause", "Start or stop auto-scroll"),
                Entry("Swipe up or down", "Scroll, with momentum"),
                Entry("Click up or down", "Scroll a step (hold to keep scrolling); faster or slower while auto-scrolling"),
                Entry("Click left or right", "Previous or next page"),
                Entry("Menu (Back)", "Close the options, then close the reader"),
            ]
        }
    }

    /// Book reader (EPUB and text) remote controls.
    public static let bookRemote: [Entry] = [
        Entry("Click or hold Select", "Reader options"),
        Entry("Play/Pause", "Reader options"),
        Entry("Swipe or click down", "Reader options"),
        Entry("Swipe or click left or right", "Turn the page"),
        Entry("Menu (Back)", "Close the options, then close the reader"),
    ]

    /// Game controller buttons (Xbox, PlayStation, MFi). Matches
    /// `GamepadMapping`.
    public static let gamepad: [Entry] = [
        Entry("Y, or Options / View / Share", "Reader options"),
        Entry("A", "Same as a click"),
        Entry("B", "Same as Menu (Back)"),
        Entry("D-pad", "Same as the remote's arrows"),
        Entry("L1 / R1 (LB / RB)", "Turn the page left or right"),
        Entry("L2 / R2 (LT / RT)", "Previous or next chapter"),
        Entry("X", "Start or stop auto-scroll (vertical reader)"),
        Entry("Either stick", "Scroll smoothly (vertical reader)"),
    ]

    /// Chapter list controls on a series page.
    public static let chapterList: [Entry] = [
        Entry("Click", "Read the chapter"),
        Entry("Move right to …, then click", "Chapter options: Mark as Read, Mark as Unread, Mark Previous as Read"),
        Entry("Hold Select on a chapter", "The same chapter options"),
        Entry("More (top of the page)", "Mark the whole series as read or unread"),
    ]

    /// The one-line hint shown the first few times a reader opens.
    public static func hint(for mode: ReadingMode) -> String {
        switch mode {
        case .paged: return "Hold Select or press Play/Pause for reader options · Click zooms · Menu closes the reader"
        case .webtoon: return "Click for reader options · Play/Pause auto-scrolls · Menu closes the reader"
        }
    }

    /// How many reader opens show the hint, unless the reader options are
    /// opened sooner (then it stops showing).
    public static let hintShowCount = 3
}

/// Remembers whether the reader's first-use hint is still needed, per
/// reading mode, on this Apple TV. The hint shows on the first
/// `ReaderControls.hintShowCount` opens of a mode and stops once the reader
/// options have been opened in that mode.
public struct ReaderHintTracker {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ mode: ReadingMode) -> String { "readerHint.\(mode.rawValue).shown" }

    /// Whether to show the hint now. Counts this open as one showing.
    public func takeHint(for mode: ReadingMode) -> Bool {
        let shown = defaults.integer(forKey: key(mode))
        guard shown < ReaderControls.hintShowCount else { return false }
        defaults.set(shown + 1, forKey: key(mode))
        return true
    }

    /// The reader options were opened: the hint did its job.
    public func menuOpened(in mode: ReadingMode) {
        defaults.set(ReaderControls.hintShowCount, forKey: key(mode))
    }

    public func reset() {
        for mode in ReadingMode.allCases { defaults.removeObject(forKey: key(mode)) }
    }
}
