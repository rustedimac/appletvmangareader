import Foundation

/// The controls tutorial (docs/READER_CONTROLS.md section 8): a short
/// reader session on a bundled sample comic where each step names one
/// remote input with a caption and waits until it's done. Offered the first
/// time a reader opens and replayable from Settings > Remote and Controller.
///
/// The inputs come from `ReaderControls`, so the tutorial can't teach a
/// button the readers don't use (`ReaderTutorialTests`).
public enum ReaderTutorial {
    /// What the reader reports when the person does something. A step is
    /// done when its goal is reported.
    public enum Goal: String, Hashable, Sendable {
        case turnPage, scroll, showPageNumber, openOptions, closeOptions
        case startPlay, changeSpeed, stopPlay, zoomIn, zoomOut, bookmark
        /// The last step: nothing to wait for; Menu closes the sample.
        case finish
    }

    public struct Step: Hashable, Sendable, Identifiable {
        /// Position in the mode's list, from 0.
        public var id: Int
        /// The input as `ReaderControls` names it ("Hold Play/Pause").
        public var input: String
        /// What to do, as a full sentence.
        public var caption: String
        /// SF Symbol for the input.
        public var symbol: String
        public var goal: Goal
    }

    /// The steps for a reading mode. The sample reads left to right, one
    /// page at a time.
    public static func steps(for mode: ReadingMode) -> [Step] {
        let o = ReaderControls.optionsInput
        let raw: [(String, String, String, Goal)]
        switch mode {
        case .paged:
            raw = [
                ("Swipe or click left or right", "Swipe right, or click the right edge of the touch surface, to turn the page.",
                 "arrow.right.circle", .turnPage),
                ("Tap the touch surface", "Tap the touch surface lightly, without clicking, to show the page number.",
                 "hand.tap", .showPageNumber),
                (o, "Hold Play/Pause for a moment to open the reader options.", "playpause.fill", .openOptions),
                ("Menu (Back)", "Press Menu to close them. Menu always closes one thing at a time.",
                 "chevron.backward.circle", .closeOptions),
                ("Hold Select", "Hold the center of the touch surface down to zoom in.",
                 "plus.magnifyingglass", .zoomIn),
                ("Click", "Click once to zoom back out.", "minus.magnifyingglass", .zoomOut),
                ("Swipe or click up", "Swipe up to bookmark the page. Do it again to remove the bookmark.",
                 "bookmark", .bookmark),
                ("Play/Pause", "Press Play/Pause to turn pages on a timer.", "play.fill", .startPlay),
                ("Play/Pause", "Press Play/Pause again to stop the timer.", "pause.fill", .stopPlay),
                ("Menu (Back)", "You're all set. Press Menu to leave the sample. Replay this any time in Settings > Remote and Controller.",
                 "checkmark.circle", .finish),
            ]
        case .webtoon:
            raw = [
                ("Swipe up or down", "Swipe up or down on the touch surface, or click its top or bottom edge, to scroll.",
                 "arrow.up.and.down.circle", .scroll),
                ("Tap the touch surface", "Tap the touch surface lightly, without clicking, to show the page number.",
                 "hand.tap", .showPageNumber),
                ("Play/Pause", "Press Play/Pause to scroll on its own.", "play.fill", .startPlay),
                ("Click up or down", "While it scrolls, click the top or bottom edge to change the speed.",
                 "speedometer", .changeSpeed),
                ("Play/Pause", "Press Play/Pause again to stop.", "pause.fill", .stopPlay),
                (o, "Hold Play/Pause for a moment to open the reader options.", "playpause.fill", .openOptions),
                ("Menu (Back)", "Press Menu to close them. Menu always closes one thing at a time.",
                 "chevron.backward.circle", .closeOptions),
                ("Menu (Back)", "You're all set. Press Menu to leave the sample. Replay this any time in Settings > Remote and Controller.",
                 "checkmark.circle", .finish),
            ]
        }
        return raw.enumerated().map { i, s in Step(id: i, input: s.0, caption: s.1, symbol: s.2, goal: s.3) }
    }

    /// Where a run of the tutorial is.
    public struct Progress: Hashable, Sendable {
        public let steps: [Step]
        public private(set) var index = 0

        public init(mode: ReadingMode) {
            steps = ReaderTutorial.steps(for: mode)
        }

        public var current: Step? { steps.indices.contains(index) ? steps[index] : nil }
        /// On the last step ("You're all set").
        public var isFinished: Bool { current?.goal == .finish }

        /// Records something the person did. Moves on and returns true when
        /// it is what the current step asks for; anything else is ignored,
        /// so trying other buttons never breaks the tutorial.
        @discardableResult
        public mutating func record(_ goal: Goal) -> Bool {
            guard let current, current.goal != .finish, current.goal == goal else { return false }
            index += 1
            return true
        }
    }

    // MARK: The sample comic

    /// Credit the CC BY 4.0 license asks for, shown in the tutorial and in
    /// Settings > Remote and Controller.
    public static let sampleCredit =
        "Sample: “Pepper&Carrot”, Episode 1: The Potion of Flight, by David Revoy (www.peppercarrot.com), "
        + "CC BY 4.0. English proofreading by Amireeti and Alex Gryson."
    /// The short form for tight spots (Settings > Remote and Controller,
    /// beside the tutorial button). The tutorial's last card shows the full
    /// `sampleCredit`, proofreaders included.
    public static let shortCredit = "Sample: “Pepper&Carrot” by David Revoy, CC BY 4.0."
    public static let sampleLicenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    /// The bundled pages, in reading order (App/Resources/Tutorial).
    public static let samplePageNames = [
        "tutorial-pepper-carrot-e01p01",
        "tutorial-pepper-carrot-e01p02",
        "tutorial-pepper-carrot-e01p03",
    ]
    /// Pixel size of every bundled page.
    public static let samplePageSize = PageSize(width: 1200, height: 1660)
}
