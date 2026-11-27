import Foundation

/// Which third of the reader a tap landed in, left to right on screen.
public enum TapRegion: Hashable, Sendable {
    case left, center, right

    /// The region of a tap at `x` in a reader `width` points wide.
    public init(x: Double, width: Double) {
        guard width > 0, x.isFinite else { self = .center; return }
        let f = x / width
        if f < 1.0 / 3 { self = .left } else if f >= 2.0 / 3 { self = .right } else { self = .center }
    }
}

/// What a tap or swipe does in a reader on a touch screen.
public enum ReaderTouchAction: Hashable, Sendable {
    /// Show or hide the reader's controls.
    case toggleChrome
    /// Paged and book readers: turn as if that side of the screen was pressed.
    case turn(ScreenDirection)
    /// Vertical reader: scroll one step forward (down) or back (up).
    case scroll(forward: Bool)
    case none
}

/// The touch rules for the readers (docs/IOS.md §3), kept here so they're
/// unit tested. The app maps gestures to these and acts on the result.
public enum ReaderTouch {
    /// Pinch zoom range in the paged reader.
    public static let maxZoom = 4.0
    /// Double-tap zooms to this, or back to fit when zoomed.
    public static let doubleTapZoom = 2.0
    /// A swipe turns when the finger travels this share of the width...
    public static let swipeDistance = 0.18
    /// ...or is flung this fast (points per second), whatever the distance.
    public static let swipeVelocity = 600.0

    /// The screen direction that moves forward in `direction`.
    public static func forwardScreenDirection(_ direction: ReadingDirection) -> ScreenDirection {
        direction == .rightToLeft ? .left : .right
    }

    /// What a single tap does.
    /// - `zoomed`: the paged reader is zoomed in; side taps don't turn then
    ///   (they'd lose the zoom), they only toggle the controls.
    public static func tap(_ region: TapRegion, zones: TapZones, mode: ReadingMode,
                           direction: ReadingDirection, zoomed: Bool = false) -> ReaderTouchAction {
        guard region != .center, zones != .off, !zoomed else { return .toggleChrome }
        let screen: ScreenDirection
        switch zones {
        case .edges: screen = region == .left ? .left : .right
        case .leftHanded: screen = forwardScreenDirection(direction)
        case .off: return .toggleChrome
        }
        switch mode {
        case .paged:
            return .turn(screen)
        case .webtoon:
            // The vertical reader always reads down; in Left and Right the
            // left third goes back up, the right third down.
            if zones == .leftHanded { return .scroll(forward: true) }
            return .scroll(forward: region == .right)
        }
    }

    /// The page turn a finished horizontal swipe asks for, if any. `dx` is
    /// the finger's travel (positive = to the right), `velocity` its speed
    /// at release, `width` the reader's width. Dragging the page to the
    /// right brings in what's on its left, like pressing left.
    public static func swipeTurn(dx: Double, dy: Double = 0, velocity: Double, width: Double) -> ScreenDirection? {
        guard width > 0, abs(dx) > abs(dy) else { return nil }
        let far = abs(dx) >= width * swipeDistance
        let fast = abs(velocity) >= swipeVelocity && abs(dx) > 20 && (velocity > 0) == (dx > 0)
        guard far || fast else { return nil }
        return dx > 0 ? .left : .right
    }

    /// Pinch result kept in range.
    public static func clampedZoom(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return 1 }
        return min(maxZoom, max(1, zoom))
    }

    /// Double-tap: zoom in to `zoomScale` (the reader's zoom setting) when
    /// at fit, back to fit when zoomed.
    public static func doubleTapTarget(currentZoom: Double, zoomScale: Double = doubleTapZoom) -> Double {
        currentZoom > 1.001 ? 1 : clampedZoom(zoomScale)
    }

    /// Two-page spreads need room: in a portrait window they'd shrink each
    /// page to a sliver, so portrait shows single pages and landscape uses
    /// the setting. The saved setting is never changed.
    public static func effectiveLayout(_ layout: PageLayout, portrait: Bool) -> PageLayout {
        portrait ? .single : layout
    }
}
