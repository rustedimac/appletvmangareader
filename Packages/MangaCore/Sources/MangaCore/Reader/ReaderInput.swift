import Foundation

// MARK: Game controllers

/// Buttons of an extended game controller (Xbox, PlayStation, MFi) that the
/// reader listens to directly. The d-pad, A and B are left to tvOS, which
/// turns them into arrow, select and Menu presses for the focus engine, so
/// they already work everywhere a Siri Remote does.
public enum GamepadButton: String, CaseIterable, Sendable {
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case buttonX
    case buttonY
    /// The small "options" / "view" / "share" button.
    case options
}

/// What a reader does in response to input that isn't a plain remote press.
public enum ReaderInputAction: Equatable, Sendable {
    /// Turn the page toward the left or right of the screen (paged), or
    /// snap to the previous / next page (vertical).
    case turnPage(ScreenDirection)
    /// Open the previous or next chapter from its first page.
    case jumpChapter(forward: Bool)
    /// Open or close the reader menu.
    case toggleMenu
    /// Start or stop webtoon auto-scroll.
    case toggleAutoScroll
}

/// Which controller button does what in the reader. Kept out of the UI so
/// the mapping is unit tested and the same in both readers.
///
/// - Shoulders (L1/R1, LB/RB) turn pages: left shoulder toward the left of
///   the screen, right shoulder toward the right, like the remote's
///   left/right, so they follow the reading direction the same way.
/// - Triggers (L2/R2, LT/RT) jump a whole chapter back or forward.
/// - X toggles auto-scroll in the vertical reader.
/// - Y or Options opens and closes the reader menu.
/// - Either stick scrolls the vertical reader smoothly (`GamepadStick`).
public enum GamepadMapping {
    /// The action for a button press. `menuOpen`: only the menu toggle
    /// works while the menu is showing, so its focus stays put.
    public static func action(for button: GamepadButton, mode: ReadingMode,
                              menuOpen: Bool = false) -> ReaderInputAction? {
        if menuOpen {
            return button == .buttonY || button == .options ? .toggleMenu : nil
        }
        switch button {
        case .leftShoulder: return .turnPage(.left)
        case .rightShoulder: return .turnPage(.right)
        case .leftTrigger: return .jumpChapter(forward: false)
        case .rightTrigger: return .jumpChapter(forward: true)
        case .buttonX: return mode == .webtoon ? .toggleAutoScroll : nil
        case .buttonY, .options: return .toggleMenu
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

/// Auto-scroll for the vertical reader: the strip moves on its own at one
/// of `levels` speeds. Speeds are fractions of the screen height per second
/// so they read the same on any screen. The level is saved per profile.
///
/// Siri Remote while it runs: Play/Pause stops it, a click stops it, swipe
/// or click up/down makes it slower/faster. A game controller's X toggles it.
public enum WebtoonAutoScroll {
    /// Screens per second at each level, slow to fast. Level 1 takes about
    /// 30 seconds per screen, level 10 about 2.
    public static let screensPerSecond: [Double] = [0.033, 0.05, 0.07, 0.09, 0.12, 0.15, 0.2, 0.26, 0.34, 0.45]
    public static var levels: ClosedRange<Int> { 1...screensPerSecond.count }
    public static let defaultLevel = 3

    public static func clamped(_ level: Int) -> Int {
        min(levels.upperBound, max(levels.lowerBound, level))
    }

    /// Points per second for `level` on a `viewport`-point-tall screen.
    public static func speed(level: Int, viewport: Double) -> Double {
        screensPerSecond[clamped(level) - 1] * viewport
    }

    public static func stepped(_ level: Int, by steps: Int) -> Int {
        clamped(clamped(level) + steps)
    }

    public static func canStep(_ level: Int, by steps: Int) -> Bool {
        stepped(level, by: steps) != clamped(level)
    }

    /// "Speed 3 of 10".
    public static func label(_ level: Int) -> String {
        "Speed \(clamped(level)) of \(levels.upperBound)"
    }

    /// A vertical swipe on the touch surface while auto-scroll runs, in
    /// points of finger travel (negative is up). Up speeds up, down slows
    /// down, one level per `perLevel` points, at least one level for any
    /// swipe past `minimum`. Returns the level change.
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
