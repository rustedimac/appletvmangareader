import Foundation

/// The two ends of a chapter. Crossing one shows a transition card first
/// ("Next: Chapter 12"), and a second press moves to the other chapter.
public enum ChapterEdge: String, Hashable, Sendable {
    case start
    case end
}

/// What a page-turn press did.
public enum PageTurnResult: Hashable, Sendable {
    /// Moved to another spread in the chapter.
    case moved
    /// Reached the chapter edge: the transition card is now showing.
    case showTransition(ChapterEdge)
    /// Pressed again on the transition card: leave the chapter this way.
    case leaveChapter(ChapterEdge)
    /// Nothing changed (empty chapter).
    case none
}

/// A press on the Siri Remote, in screen terms.
public enum ScreenDirection: Hashable, Sendable {
    case left
    case right
}

public extension ReadingDirection {
    /// Whether pressing `screen` moves forward in reading order. Right-to-left
    /// manga turns forward with a left press, like a printed book.
    func isForward(_ screen: ScreenDirection) -> Bool {
        switch (self, screen) {
        case (.leftToRight, .right), (.rightToLeft, .left): return true
        default: return false
        }
    }
}

/// Position within one chapter for the paged reader: which spread is on
/// screen, whether a transition card is showing, and how the chapter's pages
/// are grouped. Pure value type so the rules are unit tested in MangaCore;
/// `ReaderSession` in the app wraps it.
///
/// The anchor is a page, not a spread index. When page sizes arrive or
/// settings change, the spreads are recomputed and the spread containing
/// the anchor stays on screen.
public struct ReaderNavigator: Hashable, Sendable {
    public private(set) var sizes: [PageSize?]
    public private(set) var settings: ReaderSettings
    public private(set) var layout: SpreadLayout
    public private(set) var spreadIndex: Int
    /// Non-nil while a chapter transition card is on screen.
    public private(set) var edge: ChapterEdge?

    public init(sizes: [PageSize?], settings: ReaderSettings, startPage: Int = 0) {
        self.sizes = sizes
        self.settings = settings
        self.layout = settings.layout(for: sizes)
        self.spreadIndex = 0
        self.edge = nil
        self.spreadIndex = layout.spreadIndex(containing: Self.clamp(startPage, count: sizes.count))
    }

    public init(pageCount: Int, settings: ReaderSettings, startPage: Int = 0) {
        self.init(sizes: Array(repeating: nil, count: max(0, pageCount)), settings: settings, startPage: startPage)
    }

    public var pageCount: Int { sizes.count }

    public var currentSpread: Spread? {
        layout.spreads.indices.contains(spreadIndex) ? layout.spreads[spreadIndex] : nil
    }

    /// The page that anchors the current spread (its first page).
    public var currentPage: Int { currentSpread?.first ?? 0 }

    /// Pages on screen now, in reading order. Empty on a transition card.
    public var visiblePages: [Int] {
        edge == nil ? (currentSpread?.pages ?? []) : []
    }

    /// The furthest page the reader has seen in the current spread. Progress
    /// is saved with this, so finishing the last spread completes the chapter.
    public var progressPage: Int { currentSpread?.last ?? 0 }

    public var isOnLastSpread: Bool { !layout.spreads.isEmpty && spreadIndex == layout.spreads.count - 1 }
    public var isOnFirstSpread: Bool { spreadIndex == 0 }

    /// True once the last page has been on screen.
    public var isChapterComplete: Bool {
        pageCount > 0 && (progressPage >= pageCount - 1 || edge == .end)
    }

    // MARK: Turning pages

    public mutating func forward() -> PageTurnResult {
        guard !layout.spreads.isEmpty else { return .none }
        switch edge {
        case .end: return .leaveChapter(.end)
        case .start:
            edge = nil
            return .moved
        case nil:
            if isOnLastSpread {
                edge = .end
                return .showTransition(.end)
            }
            spreadIndex += 1
            return .moved
        }
    }

    public mutating func backward() -> PageTurnResult {
        guard !layout.spreads.isEmpty else { return .none }
        switch edge {
        case .start: return .leaveChapter(.start)
        case .end:
            edge = nil
            return .moved
        case nil:
            if isOnFirstSpread {
                edge = .start
                return .showTransition(.start)
            }
            spreadIndex -= 1
            return .moved
        }
    }

    /// A remote press in screen terms, mapped through the reading direction.
    public mutating func turn(_ screen: ScreenDirection) -> PageTurnResult {
        settings.direction.isForward(screen) ? forward() : backward()
    }

    /// Jumps to the spread containing `page` and hides any transition card.
    public mutating func go(toPage page: Int) {
        edge = nil
        spreadIndex = layout.spreadIndex(containing: Self.clamp(page, count: pageCount))
    }

    // MARK: Re-layout

    /// Records a page's real size. Returns true if the spreads changed.
    @discardableResult
    public mutating func setSize(_ size: PageSize, forPage page: Int) -> Bool {
        guard sizes.indices.contains(page), sizes[page] != size else { return false }
        let wasWide = sizes[page]?.isWide ?? false
        sizes[page] = size
        guard wasWide != size.isWide else { return false }
        return relayout()
    }

    /// Replaces the whole size list, e.g. after a chapter's pages load.
    @discardableResult
    public mutating func setSizes(_ newSizes: [PageSize?]) -> Bool {
        sizes = newSizes
        return relayout()
    }

    @discardableResult
    public mutating func updateSettings(_ newSettings: ReaderSettings) -> Bool {
        settings = newSettings
        return relayout()
    }

    private mutating func relayout() -> Bool {
        let anchor = currentPage
        let newLayout = settings.layout(for: sizes)
        guard newLayout != layout else { return false }
        layout = newLayout
        spreadIndex = layout.spreadIndex(containing: anchor)
        return true
    }

    // MARK: Preloading

    /// Pages of the spreads within `radius` of the current one, nearest
    /// first, so the next and previous spreads load before the rest.
    public func pagesToPreload(radius: Int = 2) -> [Int] {
        guard !layout.spreads.isEmpty else { return [] }
        var result: [Int] = []
        var offsets = [0]
        for d in stride(from: 1, through: max(0, radius), by: 1) { offsets += [d, -d] }
        for offset in offsets {
            let i = spreadIndex + offset
            guard layout.spreads.indices.contains(i) else { continue }
            result += layout.spreads[i].pages
        }
        return result
    }

    private static func clamp(_ page: Int, count: Int) -> Int {
        count == 0 ? 0 : min(max(0, page), count - 1)
    }
}

/// Where each page of a spread goes on screen. Both pages are scaled to one
/// common height and placed edge to edge with no gap, so a printed spread
/// split across two images reads as one picture. Widths are snapped to
/// whole device pixels and the second page starts exactly where the first
/// ends, which keeps a hairline seam from showing between them.
public struct PageFrame: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum SpreadGeometry {
    /// Typical manga page aspect (width / height), used until a size arrives.
    public static let placeholderAspect = 0.7

    public static func aspect(_ size: PageSize?) -> Double {
        guard let size, size.width > 0, size.height > 0 else { return placeholderAspect }
        return size.width / size.height
    }

    /// Frames for pages in screen order (left to right), fitted into a
    /// container and centered. `scale` is the screen's pixels per point.
    public static func frames(for sizes: [PageSize?], in width: Double, _ height: Double, scale: Double = 1) -> [PageFrame] {
        guard !sizes.isEmpty, width > 0, height > 0 else { return [] }
        let scale = max(1, scale)
        let aspects = sizes.map(aspect)
        let total = aspects.reduce(0, +)
        // Fit the combined strip inside the container.
        let fittedHeight = min(height, width / total)
        let h = (fittedHeight * scale).rounded(.down) / scale
        var widths = aspects.map { ($0 * h * scale).rounded() / scale }
        // Never overflow the container because of rounding.
        let overflow = widths.reduce(0, +) - width
        if overflow > 0, let last = widths.indices.last {
            widths[last] -= (overflow * scale).rounded(.up) / scale
        }
        let stripWidth = widths.reduce(0, +)
        var x = ((width - stripWidth) / 2 * scale).rounded(.down) / scale
        let y = ((height - h) / 2 * scale).rounded(.down) / scale
        var frames: [PageFrame] = []
        for w in widths {
            frames.append(PageFrame(x: x, y: y, width: w, height: h))
            x += w
        }
        return frames
    }
}
