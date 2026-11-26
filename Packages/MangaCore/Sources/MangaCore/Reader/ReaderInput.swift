import Foundation

// MARK: Game controllers

/// Buttons of a game controller (Xbox, PlayStation, MFi, and small
/// reading controllers such as the 8BitDo Micro) that the reader listens to
/// directly. The d-pad, A and B are left to tvOS, which turns them into
/// arrow, select and Menu presses for the focus engine, so they already
/// work everywhere a Siri Remote does. In the reader the d-pad only
/// navigates (docs/READER_CONTROLS.md).
public enum GamepadButton: String, CaseIterable, Sendable {
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case buttonX
    case buttonY
    /// The ☰ menu / Options / Start button.
    case menu
    /// The small "view" / "share" / "select" button.
    case options
}

/// What a reader does in response to input that isn't a plain remote press.
public enum ReaderInputAction: Equatable, Sendable {
    /// Turn the page toward the left or right of the screen (paged), or
    /// snap to the previous / next page (vertical).
    case turnPage(ScreenDirection)
    /// Open the previous or next chapter from its first page.
    case jumpChapter(forward: Bool)
    /// Open or close the reader options.
    case toggleMenu
    /// Start or stop auto-scroll (vertical) or the page-turn timer (paged):
    /// the reader's "play".
    case togglePlay
    /// Bookmark the page on screen, or remove its bookmark.
    case toggleBookmark
    /// Show or hide the page number and the other reading info.
    case toggleHUD
}

/// Which controller button does what in the reader. Kept out of the UI so
/// the mapping is unit tested and the same in every reader. Chosen with
/// John (docs/READER_CONTROLS.md section 10): it works on controllers with
/// no sticks or triggers, so nothing needs L2/R2.
///
/// - ☰ Menu opens and closes the reader options.
/// - Y bookmarks the page.
/// - X plays: auto-scroll in the vertical reader, the page-turn timer in
///   the page reader.
/// - L1 / R1 (LB / RB) open the previous / next chapter.
/// - View / Share shows or hides the page number.
/// - L2 / R2 do nothing for now.
/// - Either stick scrolls the vertical reader smoothly (`GamepadStick`).
public enum GamepadMapping {
    /// The action for a button press. `menuOpen`: only the menu toggle
    /// works while the options are showing, so their focus stays put.
    public static func action(for button: GamepadButton, mode: ReadingMode,
                              menuOpen: Bool = false) -> ReaderInputAction? {
        if menuOpen {
            return button == .menu ? .toggleMenu : nil
        }
        switch button {
        case .menu: return .toggleMenu
        case .buttonY: return .toggleBookmark
        case .buttonX: return .togglePlay
        case .leftShoulder: return .jumpChapter(forward: false)
        case .rightShoulder: return .jumpChapter(forward: true)
        case .options: return .toggleHUD
        case .leftTrigger, .rightTrigger: return nil
        }
    }
}

/// Analog stick to scroll speed for the vertical reader.
public enum GamepadStick {
    /// Stick travel ignored around the centre (worn sticks drift).
    public static let deadZone: Double = 0.15
    /// Full deflection, in screens per second.
    public static let maxScreensPerSecond: Double = 2.5

    /// Scroll speed in points per second for a stick's vertical value
    /// (-1 down ... 1 up, as GameController reports it). Positive scrolls
    /// forward (down the strip). The curve is quadratic past the dead zone,
    /// so small pushes read slowly and a full push covers ground.
    public static func scrollSpeed(y: Double, viewport: Double) -> Double {
        let magnitude = min(1, abs(y))
        guard magnitude > deadZone else { return 0 }
        let t = (magnitude - deadZone) / (1 - deadZone)
        let speed = t * t * maxScreensPerSecond * viewport
        // Stick up (positive y) scrolls back up the strip.
        return y > 0 ? -speed : speed
    }

    /// Whether the stick is pushed far enough to count as in use.
    public static func isDeflected(x: Double, y: Double) -> Bool {
        max(abs(x), abs(y)) > deadZone
    }
}

// MARK: Webtoon auto-scroll

/// Auto-scroll for the vertical reader and the page-turn timer for the page
/// reader. People pick a named speed ("Slow", "Fast"), never a number
/// (John, 2026-11-26). Internally the speed is still a level in `levels`
/// (saved per profile, so older saved values keep working); only the
/// levels in `steps` are offered, and any other saved level is shown and
/// used as its nearest step.
///
/// Siri Remote: Play/Pause starts and stops it; while it runs, swipe or
/// click up/down for slower/faster. A game controller's X toggles it.
public enum WebtoonAutoScroll {
    /// Screens per second at each level, slow to fast. Level 1 takes about
    /// 30 seconds per screen, level 10 about 2.
    public static let screensPerSecond: [Double] = [0.033, 0.05, 0.07, 0.09, 0.12, 0.15, 0.2, 0.26, 0.34, 0.45]
    public static var levels: ClosedRange<Int> { 1...screensPerSecond.count }
    /// The levels people can choose, slow to fast, with their names.
    public static let steps: [Int] = [1, 3, 5, 7, 9]
    public static let stepNames: [String] = ["Very Slow", "Slow", "Medium", "Fast", "Very Fast"]
    /// Seconds per page of the page reader's timer at each step.
    public static let pageSeconds: [Double] = [30, 20, 12, 8, 5]
    /// "Slow": today's speed before named steps.
    public static let defaultLevel = 3

    public static func clamped(_ level: Int) -> Int {
        min(levels.upperBound, max(levels.lowerBound, level))
    }

    /// Index into `steps` of the step nearest `level` (ties go to the slower one).
    public static func stepIndex(_ level: Int) -> Int {
        let level = clamped(level)
        var best = 0
        for (i, step) in steps.enumerated() where abs(step - level) < abs(steps[best] - level) {
            best = i
        }
        return best
    }

    /// The offered level nearest `level`.
    public static func nearestStep(_ level: Int) -> Int { steps[stepIndex(level)] }

    /// Points per second for `level` on a `viewport`-point-tall screen.
    public static func speed(level: Int, viewport: Double) -> Double {
        screensPerSecond[clamped(level) - 1] * viewport
    }

    /// The level `by` steps faster (positive) or slower from `level`.
    public static func stepped(_ level: Int, by steps: Int) -> Int {
        let i = min(self.steps.count - 1, max(0, stepIndex(level) + steps))
        return self.steps[i]
    }

    public static func canStep(_ level: Int, by steps: Int) -> Bool {
        stepped(level, by: steps) != nearestStep(level)
    }

    /// "Slow". Never a number.
    public static func label(_ level: Int) -> String {
        stepNames[stepIndex(level)]
    }

    /// Seconds per page for the page reader's timer at `level`.
    public static func secondsPerPage(_ level: Int) -> Double {
        pageSeconds[stepIndex(level)]
    }

    /// A vertical swipe on the touch surface while auto-scroll runs, in
    /// points of finger travel (negative is up). Up speeds up, down slows
    /// down, one step per `perLevel` points, at least one step for any
    /// swipe past `minimum`. Returns the step change.
    public static func levelChange(forSwipe translationY: Double, minimum: Double = 40,
                                   perLevel: Double = 250) -> Int {
        guard abs(translationY) >= minimum else { return 0 }
        let steps = max(1, Int((abs(translationY) / perLevel).rounded()))
        return translationY < 0 ? steps : -steps
    }

    /// Where auto-scroll is after `dt` seconds, or nil when it has reached
    /// the end and should stop. `atEnd` says the strip has nothing more to
    /// load below (otherwise it waits at the bottom for the next chapter).
    public static func advance(offset: Double, dt: Double, level: Int, viewport: Double,
                               maxOffset: Double, atEnd: Bool) -> Double? {
        if offset >= maxOffset - 0.5 {
            return atEnd ? nil : maxOffset
        }
        return min(maxOffset, offset + speed(level: level, viewport: viewport) * dt)
    }
}

public extension ProfileData {
    /// The profile's webtoon auto-scroll speed level.
    var autoScrollLevel: Int {
        get { WebtoonAutoScroll.clamped(webtoonAutoScrollLevel ?? WebtoonAutoScroll.defaultLevel) }
        set { webtoonAutoScrollLevel = WebtoonAutoScroll.clamped(newValue) }
    }
}

public extension AppState {
    func autoScrollLevel(profile: UUID) -> Int {
        profileData[profile.uuidString]?.autoScrollLevel ?? WebtoonAutoScroll.defaultLevel
    }

    mutating func setAutoScrollLevel(_ level: Int, profile: UUID) {
        mutateData(profile) { $0.autoScrollLevel = level }
    }
}
