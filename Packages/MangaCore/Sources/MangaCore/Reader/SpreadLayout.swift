import Foundation

/// One side of a page image, for wide pages split into two screens.
public enum PageHalf: String, Hashable, Sendable {
    case left
    case right
}

/// What the paged reader shows at one time: one page, two pages side by
/// side, or one half of a wide page (a scanned two-page spread split for
/// single-page reading). Indices are zero-based page indices in reading
/// order.
public enum Spread: Hashable, Sendable {
    case single(Int)
    case double(Int, Int)
    /// One half of a wide page. Both halves belong to the same page, so
    /// progress, bookmarks and the page indicator all use that page.
    case half(Int, PageHalf)

    public var pages: [Int] {
        switch self {
        case .single(let a): return [a]
        case .double(let a, let b): return [a, b]
        case .half(let a, _): return [a]
        }
    }

    /// The side of the image on screen, for split pages.
    public var half: PageHalf? {
        if case .half(_, let side) = self { return side }
        return nil
    }

    public var first: Int { pages[0] }
    public var last: Int { pages[pages.count - 1] }

    public func contains(_ page: Int) -> Bool { pages.contains(page) }

    /// Pages in on-screen order, left to right. Right-to-left manga puts the
    /// earlier page on the right.
    public func screenOrder(_ direction: ReadingDirection) -> [Int] {
        direction == .rightToLeft ? pages.reversed() : pages
    }
}

/// Groups a chapter's pages into spreads for the double-page reader.
///
/// The hard part of double-page reading is parity: books are printed so that
/// page 1 is alone (a cover or a right-hand page) and pairs start at 2-3.
/// If the reader pairs from page 1 instead, every pair is off by one and the
/// two halves of a printed spread end up on different screens. The rules:
///
/// 1. A wide page (already a full spread in one image) is always shown alone.
/// 2. If `firstPageAlone` is on, page 0 is shown alone (cover / first page).
/// 3. Otherwise pages are paired in order. After a wide page, pairing starts
///    fresh, because a scanlator who joined a spread into one image has
///    already fixed the parity for what follows.
/// 4. A page that would be paired with a wide page is shown alone instead.
/// 5. `shift` flips the parity of the first run of paired pages. It's the
///    user's escape hatch for when the guess is wrong.
///
/// Pages with unknown size are treated as normal (not wide). The reader
/// relays out once sizes arrive, keeping the current page in view.
public struct SpreadLayout: Hashable, Sendable {
    public var spreads: [Spread]

    public init(pageCount: Int, isWide: (Int) -> Bool, firstPageAlone: Bool, shift: Bool) {
        var result: [Spread] = []
        var i = 0
        // `firstPageAlone` XOR `shift` decides whether page 0 stands alone.
        var startAlone = firstPageAlone != shift
        while i < pageCount {
            if isWide(i) {
                result.append(.single(i))
                i += 1
                startAlone = false
                continue
            }
            if startAlone {
                result.append(.single(i))
                i += 1
                startAlone = false
                continue
            }
            let next = i + 1
            if next < pageCount, !isWide(next) {
                result.append(.double(i, next))
                i += 2
            } else {
                result.append(.single(i))
                i += 1
            }
        }
        spreads = result
    }

    public init(sizes: [PageSize?], firstPageAlone: Bool, shift: Bool) {
        self.init(pageCount: sizes.count,
                  isWide: { sizes[$0]?.isWide ?? false },
                  firstPageAlone: firstPageAlone,
                  shift: shift)
    }

    /// Single-page layout: one spread per page.
    public static func singles(pageCount: Int) -> SpreadLayout {
        SpreadLayout(spreads: (0..<pageCount).map { .single($0) })
    }

    /// Single-page layout with wide pages split in two. Each wide page
    /// becomes two screens in reading order: right half first for
    /// right-to-left manga, left half first otherwise. Pages with unknown
    /// size stay whole until their size arrives.
    public static func singles(splitting sizes: [PageSize?], direction: ReadingDirection) -> SpreadLayout {
        let order: [PageHalf] = direction == .rightToLeft ? [.right, .left] : [.left, .right]
        var spreads: [Spread] = []
        for (i, size) in sizes.enumerated() {
            if size?.isWide == true {
                spreads += order.map { .half(i, $0) }
            } else {
                spreads.append(.single(i))
            }
        }
        return SpreadLayout(spreads: spreads)
    }

    public init(spreads: [Spread]) {
        self.spreads = spreads
    }

    public var count: Int { spreads.count }

    /// The spread to keep on screen across a re-layout: the same spread if
    /// it still exists (so the second half of a split page stays the second
    /// half), otherwise the first spread containing `page`.
    public func spreadIndex(keeping spread: Spread?, page: Int) -> Int {
        if let spread, let idx = spreads.firstIndex(of: spread) { return idx }
        return spreadIndex(containing: page)
    }

    /// The spread containing a page, for resuming and re-layouts.
    public func spreadIndex(containing page: Int) -> Int {
        guard !spreads.isEmpty else { return 0 }
        if let idx = spreads.firstIndex(where: { $0.contains(page) }) { return idx }
        return page < 0 ? 0 : spreads.count - 1
    }
}

/// Decides when a run of pages probably has the wrong parity, so the reader
/// can fix it without the user noticing. Used for pages whose sizes we only
/// learn while reading (Suwayomi).
public enum SpreadHeuristics {
    /// If the chapter's first page is wide (a color spread as the opener),
    /// it is not a cover, so the first page should not stand alone by itself
    /// beyond being wide. Returns the recommended `firstPageAlone` value.
    public static func recommendedFirstPageAlone(sizes: [PageSize?], userDefault: Bool) -> Bool {
        if let first = sizes.first, let size = first, size.isWide { return false }
        return userDefault
    }
}
