import Foundation

/// The reader's button map, in one place, so the Settings "Remote and
/// Controller" screen, the Controls list at the bottom of the reader
/// options, the first-use hint and docs/CONTROLS.md all say the same thing
/// as the readers do.
///
/// The scheme John chose (docs/READER_CONTROLS.md section 10): one input
/// per action. Play/Pause plays (auto-scroll, or the page-turn timer) and
/// **holding Play/Pause opens the reader options**, which are deliberately
/// not one easy press away. A tap on the touch surface (not a click) shows
/// the page number for a few seconds. Holding Select zooms in, a click
/// zooms out. Menu (Back) closes one layer at a time before leaving.
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

    /// "Hold Play/Pause": the route to the reader options everywhere.
    public static let optionsInput = "Hold Play/Pause"

    /// Siri Remote controls for a reading mode.
    public static func remote(for mode: ReadingMode) -> [Entry] {
        switch mode {
        case .paged:
            return [
                Entry(optionsInput, "Reader options"),
                Entry("Play/Pause", "Turn pages on a timer (start or stop)"),
                Entry("Tap the touch surface", "Show the page number"),
                Entry("Swipe or click left or right", "Turn the page (follows the reading direction)"),
                Entry("Swipe or click up", "Bookmark the page, or remove the bookmark"),
                Entry("Swipe or click down", "Page thumbnails"),
                Entry("Hold Select", "Zoom in"),
                Entry("Click", "Zoom out, or retry a page that didn't load"),
                Entry("Menu (Back)", "Close what's open, zoom out, then close the reader"),
            ]
        case .webtoon:
            return [
                Entry(optionsInput, "Reader options"),
                Entry("Play/Pause", "Start or stop auto-scroll"),
                Entry("Tap the touch surface", "Show the page number"),
                Entry("Swipe up or down", "Scroll, with momentum; while auto-scrolling, faster or slower"),
                Entry("Click up or down", "Scroll a step (hold to keep scrolling); while auto-scrolling, faster or slower"),
                Entry("Click left or right", "Previous or next page"),
                Entry("Click", "Retry a page that didn't load"),
                Entry("Menu (Back)", "Close what's open, stop auto-scroll, then close the reader"),
            ]
        }
    }

    /// Book reader (EPUB and text) remote controls.
    public static let bookRemote: [Entry] = [
        Entry(optionsInput, "Reader options"),
        Entry("Swipe or click left or right", "Turn the page"),
        Entry("Menu (Back)", "Close the options, then close the book"),
    ]

    /// Game controller buttons (Xbox, PlayStation, MFi, 8BitDo and other
    /// small controllers). Matches `GamepadMapping`.
    public static let gamepad: [Entry] = [
        Entry("☰ Menu / Options / Start", "Reader options"),
        Entry("D-pad", "Navigate: turn pages (page reader) or scroll (vertical reader)"),
        Entry("A", "Same as a click; hold to zoom in"),
        Entry("B", "Same as Menu (Back)"),
        Entry("Y", "Bookmark the page"),
        Entry("X", "Auto-scroll, or turn pages on a timer"),
        Entry("L1 / R1 (LB / RB)", "Previous or next chapter"),
        Entry("View / Share / Select", "Show the page number"),
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
        case .paged: return "Hold Play/Pause for reader options · Tap to show the page number · Menu closes the reader"
        case .webtoon: return "Hold Play/Pause for reader options · Play/Pause auto-scrolls · Menu closes the reader"
        }
    }

    /// The corner hint shown with the page number: next to a Play/Pause icon.
    public static let hudHint = "Hold for options"

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
