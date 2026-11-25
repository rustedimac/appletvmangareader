import Foundation

// Layout math for the webtoon (continuous vertical) reader. Everything is in
// whole device pixels so pages stack with no seams: every page's top is the
// previous page's bottom, both integers, and the view divides by the screen
// scale only when it sets frames. Pure value types, tested in MangaCore.

/// One chapter in the strip: its id and the page sizes known so far.
public struct WebtoonSegment: Hashable, Sendable {
    public var id: String
    public var sizes: [PageSize?]

    public init(id: String, sizes: [PageSize?]) {
        self.id = id
        self.sizes = sizes
    }
}

public enum WebtoonGeometry {
    /// Column width in device pixels for a screen `screenPixels` wide.
    /// It has the same parity as the screen so it centers on a whole pixel.
    public static func columnPixels(screenPixels: Int, fraction: Double) -> Int {
        guard screenPixels > 0 else { return 0 }
        let f = min(1.0, max(0.3, fraction))
        var w = Int((Double(screenPixels) * f).rounded())
        if (screenPixels - w) % 2 != 0 { w -= 1 }
        return max(2, min(screenPixels, w))
    }

    /// Left edge of the centered column, in device pixels.
    public static func columnX(screenPixels: Int, columnPixels: Int) -> Int {
        max(0, (screenPixels - columnPixels) / 2)
    }

    /// Height of a page drawn `columnPixels` wide. Uses `estimate`
    /// (width / height) until the real size is known. Always at least 1.
    public static func pageHeightPixels(_ size: PageSize?, columnPixels: Int, estimate: Double) -> Int {
        let aspect: Double
        if let size, size.width > 0, size.height > 0 {
            aspect = size.width / size.height
        } else {
            aspect = estimate > 0 ? estimate : SpreadGeometry.placeholderAspect
        }
        return max(1, Int((Double(columnPixels) / aspect).rounded()))
    }

    /// Best guess for pages whose size isn't known yet: the median aspect
    /// of the known ones (webtoon pages in a chapter are usually the same
    /// width and similar heights), else a typical manga page.
    public static func estimatedAspect(known: [PageSize]) -> Double {
        let aspects = known.filter { $0.width > 0 && $0.height > 0 }.map { $0.width / $0.height }.sorted()
        guard !aspects.isEmpty else { return SpreadGeometry.placeholderAspect }
        let mid = aspects.count / 2
        return aspects.count % 2 == 1 ? aspects[mid] : (aspects[mid - 1] + aspects[mid]) / 2
    }
}

/// Something in the strip.
public enum WebtoonItemKind: Hashable, Sendable {
    /// A page of a chapter (segment id, zero-based page index).
    case page(segment: String, page: Int)
    /// The divider shown above a chapter that follows another one.
    case chapterBreak(before: String)
    /// The footer after the last chapter of the series.
    case end
}

public struct WebtoonItem: Hashable, Sendable {
    public var kind: WebtoonItemKind
    /// Top edge in device pixels from the top of the strip.
    public var y: Int
    public var height: Int
    public var maxY: Int { y + height }

    public var segment: String? {
        switch kind {
        case .page(let s, _): return s
        case .chapterBreak(let s): return s
        case .end: return nil
        }
    }
}

/// Where everything in the strip goes.
public struct WebtoonLayout: Hashable, Sendable {
    public private(set) var items: [WebtoonItem]
    public private(set) var totalHeight: Int
    public let columnPixels: Int
    private var pageIndex: [String: [Int]] = [:]

    /// - Parameters:
    ///   - segments: chapters in reading order.
    ///   - breakHeight: height of the divider between two chapters.
    ///   - endHeight: height of the footer after the last segment; 0 for none.
    public init(segments: [WebtoonSegment], columnPixels: Int, breakHeight: Int, endHeight: Int = 0) {
        self.columnPixels = columnPixels
        let allKnown = segments.flatMap { $0.sizes.compactMap { $0 } }
        let fallback = WebtoonGeometry.estimatedAspect(known: allKnown)
        var items: [WebtoonItem] = []
        var index: [String: [Int]] = [:]
        var y = 0
        for (s, segment) in segments.enumerated() {
            if s > 0, breakHeight > 0 {
                items.append(WebtoonItem(kind: .chapterBreak(before: segment.id), y: y, height: breakHeight))
                y += breakHeight
            }
            let known = segment.sizes.compactMap { $0 }
            let estimate = known.isEmpty ? fallback : WebtoonGeometry.estimatedAspect(known: known)
            var rows: [Int] = []
            rows.reserveCapacity(segment.sizes.count)
            for (p, size) in segment.sizes.enumerated() {
                let h = WebtoonGeometry.pageHeightPixels(size, columnPixels: columnPixels, estimate: estimate)
                rows.append(items.count)
                items.append(WebtoonItem(kind: .page(segment: segment.id, page: p), y: y, height: h))
                y += h
            }
            index[segment.id] = rows
        }
        if endHeight > 0, !segments.isEmpty {
            items.append(WebtoonItem(kind: .end, y: y, height: endHeight))
            y += endHeight
        }
        self.items = items
        self.totalHeight = y
        self.pageIndex = index
    }

    /// Index of the item covering `y` (clamped to the strip).
    public func itemIndex(atY y: Int) -> Int? {
        guard !items.isEmpty else { return nil }
        if y <= 0 { return 0 }
        if y >= totalHeight { return items.count - 1 }
        var lo = 0, hi = items.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if items[mid].y <= y { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Items that intersect `minY..<maxY`.
    public func itemIndices(from minY: Int, to maxY: Int) -> Range<Int> {
        guard let first = itemIndex(atY: minY), maxY > minY else { return 0..<0 }
        var last = first
        while last + 1 < items.count, items[last + 1].y < maxY { last += 1 }
        return first..<(last + 1)
    }

    public func itemIndex(segment: String, page: Int) -> Int? {
        guard let rows = pageIndex[segment], !rows.isEmpty else { return nil }
        return rows[min(max(0, page), rows.count - 1)]
    }

    public func item(segment: String, page: Int) -> WebtoonItem? {
        itemIndex(segment: segment, page: page).map { items[$0] }
    }

    public func pageCount(segment: String) -> Int { pageIndex[segment]?.count ?? 0 }

    public func index(of kind: WebtoonItemKind) -> Int? {
        switch kind {
        case .page(let s, let p):
            guard let rows = pageIndex[s], rows.indices.contains(p) else { return nil }
            return rows[p]
        default:
            return items.firstIndex { $0.kind == kind }
        }
    }

    /// The page a reader looking at `topY..<bottomY` is on, for progress:
    /// the page at the top of the screen, or the chapter's last page once
    /// its bottom edge is on screen (so finishing a chapter counts even
    /// though its last page never reaches the top). A chapter divider at
    /// the top counts as the start of the chapter below it.
    public func readingPosition(topY: Int, bottomY: Int) -> (segment: String, page: Int)? {
        guard var i = itemIndex(atY: topY) else { return nil }
        switch items[i].kind {
        case .chapterBreak:
            if i + 1 < items.count { i += 1 }
        case .end:
            // Back up to the last page.
            while i > 0, case .end = items[i].kind { i -= 1 }
        case .page:
            break
        }
        guard case .page(let segment, let page) = items[i].kind else { return nil }
        let count = pageCount(segment: segment)
        if let last = item(segment: segment, page: count - 1), last.maxY <= bottomY {
            return (segment, count - 1)
        }
        return (segment, page)
    }

    /// Largest valid scroll offset for a viewport `viewport` pixels tall.
    public func maxOffset(viewport: Int) -> Int { max(0, totalHeight - viewport) }
}

/// A scroll position that survives re-layouts: the item at the top of the
/// screen and how far into it the top edge is. When pages above it change
/// height (sizes arrive, a chapter is added or dropped above) the item stays
/// exactly where it was on screen, so the content never jumps.
public struct WebtoonAnchor: Hashable, Sendable {
    public var kind: WebtoonItemKind
    /// Offset into the item, in pixels, as of the layout it was captured in.
    public var offset: Int
    /// The item's height when captured, to scale `offset` if it changes.
    public var height: Int

    public init(kind: WebtoonItemKind, offset: Int, height: Int) {
        self.kind = kind
        self.offset = offset
        self.height = height
    }

    public static func capture(_ layout: WebtoonLayout, offsetY: Int) -> WebtoonAnchor? {
        guard let i = layout.itemIndex(atY: offsetY) else { return nil }
        let item = layout.items[i]
        return WebtoonAnchor(kind: item.kind, offset: offsetY - item.y, height: item.height)
    }

    /// The offset that puts the anchor back where it was in `layout`, or nil
    /// if the anchored item is gone. If the anchored item itself changed
    /// height, the position within it is kept proportionally.
    public func resolve(in layout: WebtoonLayout) -> Int? {
        guard let i = layout.index(of: kind) else { return nil }
        let item = layout.items[i]
        let inside: Int
        if item.height == height || height <= 0 {
            inside = offset
        } else {
            inside = Int((Double(offset) * Double(item.height) / Double(height)).rounded())
        }
        return item.y + min(max(0, inside), max(0, item.height - 1))
    }
}

/// Remote-driven scrolling helpers.
public enum WebtoonScrolling {
    /// Where one click up or down moves to: `step` (a fraction of the
    /// viewport) further, clamped to the strip.
    public static func stepTarget(from offset: Double, forward: Bool, viewport: Double, step: Double,
                                  maxOffset: Double) -> Double {
        let amount = viewport * min(1.0, max(0.1, step))
        let target = offset + (forward ? amount : -amount)
        return min(max(0, target), max(0, maxOffset))
    }

    /// Speed (points per second) while a direction is held, ramping up so a
    /// short hold is controllable and a long one covers ground.
    public static func holdSpeed(heldFor seconds: Double, viewport: Double) -> Double {
        let start = viewport * 1.0
        let top = viewport * 3.0
        let ramp = 1.5
        let t = min(1.0, max(0.0, seconds / ramp))
        return start + (top - start) * t
    }

    /// Whether the reader is close enough to the end of the strip to load
    /// the next chapter (`screens` viewports away or less).
    public static func nearEnd(offset: Int, viewport: Int, totalHeight: Int, screens: Double = 2) -> Bool {
        Double(totalHeight - (offset + viewport)) < Double(viewport) * screens
    }

    public static func nearStart(offset: Int, viewport: Int, screens: Double = 1) -> Bool {
        Double(offset) < Double(viewport) * screens
    }
}

/// How a page image is decoded and split for display. Huge strips (some
/// webtoon pages are 20,000 pixels tall) can't go in one GPU texture or in
/// memory at full screen resolution, so the page is decoded at 1/`factor`
/// of its display size and cut into tiles of at most `maxTileRows` rows.
/// Each tile maps to a whole number of display pixels, so tiles join with
/// no seam just like pages do.
public struct WebtoonTilePlan: Hashable, Sendable {
    public struct Tile: Hashable, Sendable {
        /// Rows of the decoded image.
        public var sourceY: Int
        public var sourceHeight: Int
        /// Display pixels, relative to the page's top.
        public var displayY: Int
        public var displayHeight: Int
    }

    public var decodeWidth: Int
    public var decodeHeight: Int
    public var tiles: [Tile]
    /// True when the decoded image must be exactly `decodeWidth` ×
    /// `decodeHeight` (multi-tile pages), not just close to it.
    public var requiresExactSize: Bool { tiles.count > 1 }

    public init(source: PageSize, displayWidth: Int, displayHeight: Int,
                maxTileRows: Int = 4096, maxBytes: Int = 48 << 20) {
        let sw = max(1, Int(source.width.rounded()))
        let sh = max(1, Int(source.height.rounded()))
        let dw = max(1, displayWidth)
        let dh = max(1, displayHeight)
        let rows = max(64, maxTileRows)

        // One tile: decode at the display size, or the source size if that
        // is smaller (never upscale in memory; the layer stretches it).
        var w = min(dw, sw)
        var h = max(1, Int((Double(sh) * Double(w) / Double(sw)).rounded()))
        while w * h * 4 > maxBytes, w > 1 {
            w = max(1, w * 3 / 4)
            h = max(1, Int((Double(sh) * Double(w) / Double(sw)).rounded()))
        }
        if h <= rows {
            decodeWidth = w
            decodeHeight = h
            tiles = [Tile(sourceY: 0, sourceHeight: h, displayY: 0, displayHeight: dh)]
            return
        }

        // Several tiles: decode at display size / k for a whole k, so every
        // decoded row maps to exactly k display rows.
        var k = max(1, dh / sh)
        func size(_ k: Int) -> (Int, Int) {
            ((dw + k - 1) / k, (dh + k - 1) / k)
        }
        while size(k).0 * size(k).1 * 4 > maxBytes, k < dh { k += 1 }
        let (cw, ch) = size(k)
        decodeWidth = cw
        decodeHeight = ch
        var result: [Tile] = []
        var y = 0
        while y < ch {
            let n = min(rows, ch - y)
            let displayY = y * k
            let isLast = y + n >= ch
            let displayH = isLast ? dh - displayY : n * k
            result.append(Tile(sourceY: y, sourceHeight: n, displayY: displayY, displayHeight: displayH))
            y += n
        }
        tiles = result
    }
}
