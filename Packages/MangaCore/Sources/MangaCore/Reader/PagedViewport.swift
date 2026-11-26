import Foundation

/// A width and height in points.
public struct Extent: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Extent(width: 0, height: 0)
}

/// A spread laid out for a fit mode: page frames inside a canvas that is at
/// least the size of the screen. With Fit Screen the canvas is the screen.
/// With Fit Width a tall spread makes the canvas taller than the screen,
/// and with Fit Height a wide spread makes it wider; the reader pans over it.
public struct SpreadCanvas: Hashable, Sendable {
    public var frames: [PageFrame]
    public var size: Extent

    public init(frames: [PageFrame], size: Extent) {
        self.frames = frames
        self.size = size
    }
}

public extension SpreadGeometry {
    /// Frames for pages in screen order under a fit mode. Like
    /// `frames(for:in:_:scale:)`, pages share one height, touch with no
    /// gap, and are snapped to device pixels. A spread smaller than the
    /// screen along an axis is centered on it.
    static func canvas(for sizes: [PageSize?], in width: Double, _ height: Double,
                       fit: PageFit, scale: Double = 1) -> SpreadCanvas {
        guard !sizes.isEmpty, width > 0, height > 0 else {
            return SpreadCanvas(frames: [], size: Extent(width: max(0, width), height: max(0, height)))
        }
        let scale = max(1, scale)
        let total = sizes.map(aspect).reduce(0, +)
        let fittedHeight: Double
        switch fit {
        case .screen: fittedHeight = min(height, width / total)
        case .width: fittedHeight = width / total
        case .height: fittedHeight = height
        }
        let h = (fittedHeight * scale).rounded(.down) / scale
        var widths = sizes.map { (aspect($0) * h * scale).rounded() / scale }
        // Width-limited fits must not overflow the screen because of rounding.
        if fit != .height || widths.reduce(0, +) - width < 1 / scale {
            let overflow = widths.reduce(0, +) - width
            if overflow > 0, let last = widths.indices.last {
                widths[last] -= (overflow * scale).rounded(.up) / scale
            }
        }
        let stripWidth = widths.reduce(0, +)
        let canvas = Extent(width: max(width, stripWidth), height: max(height, h))
        var x = ((canvas.width - stripWidth) / 2 * scale).rounded(.down) / scale
        let y = ((canvas.height - h) / 2 * scale).rounded(.down) / scale
        var frames: [PageFrame] = []
        for w in widths {
            frames.append(PageFrame(x: x, y: y, width: w, height: h))
            x += w
        }
        return SpreadCanvas(frames: frames, size: canvas)
    }
}

/// Which way the remote asks the view to move.
public enum PanDirection: Hashable, Sendable, CaseIterable {
    case up, down, left, right
}

/// Zoom and pan over a spread's canvas. Position is kept as a fraction of
/// how far the view can travel on each axis (0 = left/top edge, 1 =
/// right/bottom edge), so it stays valid when the canvas changes size
/// (an image size arrives, a crop is found, the fit mode changes).
public struct PagedViewport: Hashable, Sendable {
    public var zoom: Double
    public var x: Double
    public var y: Double

    public init(zoom: Double = 1, x: Double = 0.5, y: Double = 0) {
        self.zoom = max(1, zoom)
        self.x = Self.unit(x)
        self.y = Self.unit(y)
    }

    /// Where a page opens when reached by reading forward: the top, on the
    /// side reading starts from (right for right-to-left manga).
    public static func start(_ direction: ReadingDirection) -> PagedViewport {
        PagedViewport(zoom: 1, x: direction == .rightToLeft ? 1 : 0, y: 0)
    }

    /// Where a page opens when reached by reading backward: the bottom, on
    /// the side reading ends at.
    public static func end(_ direction: ReadingDirection) -> PagedViewport {
        PagedViewport(zoom: 1, x: direction == .rightToLeft ? 0 : 1, y: 1)
    }

    public var isZoomed: Bool { zoom > 1.001 }

    /// How far the view can travel on each axis, in points.
    public func travel(canvas: Extent, screen: Extent) -> Extent {
        Extent(width: max(0, canvas.width * zoom - screen.width),
               height: max(0, canvas.height * zoom - screen.height))
    }

    /// The top-left of the screen within the zoomed canvas, in points.
    /// Draw the canvas scaled by `zoom` from its top-left, offset by minus this.
    public func offset(canvas: Extent, screen: Extent, scale: Double = 1) -> (x: Double, y: Double) {
        let t = travel(canvas: canvas, screen: screen)
        let s = max(1, scale)
        return ((x * t.width * s).rounded() / s, (y * t.height * s).rounded() / s)
    }

    /// Whether the view can move that way (more of the canvas lies there).
    public func canPan(_ direction: PanDirection, canvas: Extent, screen: Extent) -> Bool {
        let t = travel(canvas: canvas, screen: screen)
        let eps = 0.5
        switch direction {
        case .left: return t.width > eps && x > 0.0001
        case .right: return t.width > eps && x < 0.9999
        case .up: return t.height > eps && y > 0.0001
        case .down: return t.height > eps && y < 0.9999
        }
    }

    /// Moves by `step` of a screen (clamped to the canvas edge).
    public func panned(_ direction: PanDirection, step: Double, canvas: Extent, screen: Extent) -> PagedViewport {
        let t = travel(canvas: canvas, screen: screen)
        var v = self
        switch direction {
        case .left, .right:
            guard t.width > 0 else { return v }
            let d = screen.width * step / t.width
            v.x = Self.unit(x + (direction == .right ? d : -d))
        case .up, .down:
            guard t.height > 0 else { return v }
            let d = screen.height * step / t.height
            v.y = Self.unit(y + (direction == .down ? d : -d))
        }
        return v
    }

    /// Moves with a finger on the touch surface: the canvas follows the
    /// finger, so dragging right shows more of the left. `dx`/`dy` are in
    /// screen points, scaled by `gain`, and the result is clamped to the
    /// canvas edges.
    public func dragged(dx: Double, dy: Double, gain: Double = 1, canvas: Extent, screen: Extent) -> PagedViewport {
        let t = travel(canvas: canvas, screen: screen)
        var v = self
        if t.width > 0 { v.x = Self.unit(x - dx * gain / t.width) }
        if t.height > 0 { v.y = Self.unit(y - dy * gain / t.height) }
        return v
    }

    /// Whether there is anything to drag (the canvas is bigger than the screen).
    public func canDrag(canvas: Extent, screen: Extent) -> Bool {
        let t = travel(canvas: canvas, screen: screen)
        return t.width > 0.5 || t.height > 0.5
    }

    /// Changes magnification keeping the point at the center of the screen
    /// where it is.
    public func zoomed(to newZoom: Double, canvas: Extent, screen: Extent) -> PagedViewport {
        let newZoom = max(1, newZoom)
        let old = travel(canvas: canvas, screen: screen)
        var v = self
        v.zoom = newZoom
        let new = v.travel(canvas: canvas, screen: screen)
        // Canvas point at the screen's center, as a fraction of the canvas.
        func center(_ pos: Double, _ travel: Double, _ screenLen: Double, _ canvasLen: Double, _ z: Double) -> Double {
            guard canvasLen > 0 else { return 0.5 }
            return (pos * travel + screenLen / 2) / (canvasLen * z)
        }
        func position(_ c: Double, _ travel: Double, _ screenLen: Double, _ canvasLen: Double, _ z: Double) -> Double {
            guard travel > 0 else { return 0.5 }
            return Self.unit((c * canvasLen * z - screenLen / 2) / travel)
        }
        let cx = center(x, old.width, screen.width, canvas.width, zoom)
        let cy = center(y, old.height, screen.height, canvas.height, zoom)
        v.x = position(cx, new.width, screen.width, canvas.width, newZoom)
        v.y = position(cy, new.height, screen.height, canvas.height, newZoom)
        return v
    }

    private static func unit(_ v: Double) -> Double { min(1, max(0, v.isFinite ? v : 0)) }
}

/// What a remote press does in the paged reader.
public enum PagedRemoteAction: Hashable, Sendable {
    /// Move the view over the current spread.
    case pan(PagedViewport)
    /// Turn the page (or reach a chapter edge) this way on screen.
    case turn(ScreenDirection)
    case openMenu
    case none
}

/// The paged reader's remote rules, kept here so they're unit tested.
///
/// - Left/right follow the reading direction. While there is more of the
///   spread that way (zoomed in, or Fit Height on a wide spread) they pan
///   there; pressed toward an edge the view is already at, they turn the
///   page. Up/down (or a finger on the touch surface) move vertically.
///   With no sideways room (Fit Width), forward scrolls down and backward
///   up before turning.
/// - Up/down pan when the spread is taller than the screen (Fit Width,
///   zoom). Down opens the menu only when there's nothing below.
public enum PagedRemote {
    /// Share of a screen each press pans.
    public static let step = 0.8

    public static func action(for press: PanDirection, viewport: PagedViewport, canvas: Extent,
                              screen: Extent, direction: ReadingDirection) -> PagedRemoteAction {
        let canPan = { (d: PanDirection) in viewport.canPan(d, canvas: canvas, screen: screen) }
        switch press {
        case .up:
            return canPan(.up) ? .pan(viewport.panned(.up, step: step, canvas: canvas, screen: screen)) : .none
        case .down:
            if canPan(.down) { return .pan(viewport.panned(.down, step: step, canvas: canvas, screen: screen)) }
            let t = viewport.travel(canvas: canvas, screen: screen)
            return t.height > 0.5 ? .none : .openMenu
        case .left, .right:
            let screenDirection: ScreenDirection = press == .left ? .left : .right
            if canPan(press) {
                return .pan(viewport.panned(press, step: step, canvas: canvas, screen: screen))
            }
            // Sideways room (zoomed, Fit Height): a press toward the edge
            // you're already at turns the page, wherever you are vertically.
            if viewport.travel(canvas: canvas, screen: screen).width > 0.5 {
                return .turn(screenDirection)
            }
            // A page only taller than the screen (Fit Width) reads down
            // with forward and back up with backward before turning.
            let forward = direction.isForward(screenDirection)
            let vertical: PanDirection = forward ? .down : .up
            if canPan(vertical) {
                return .pan(viewport.panned(vertical, step: step, canvas: canvas, screen: screen))
            }
            return .turn(screenDirection)
        }
    }
}
