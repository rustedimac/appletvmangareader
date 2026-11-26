import Foundation

/// The rules behind the page scrubber: a strip of page thumbnails with a
/// progress bar, opened from the reader menu. Kept out of the UI so they
/// can be unit tested.
///
/// - Thumbnails run in screen order: page 1 on the left for left-to-right
///   books, page 1 on the right for right-to-left manga, so moving focus
///   the way you turn pages moves forward through the chapter.
/// - Left/right moves one page (focus does that), up jumps 10 pages back
///   and down 10 pages forward, clamped to the chapter.
/// - Clicking a thumbnail opens that page.
public enum PageScrubber {
    /// Pages jumped by one press up or down.
    public static let jumpSize = 10

    /// Page indices in on-screen order, left to right.
    public static func screenOrder(pageCount: Int, direction: ReadingDirection) -> [Int] {
        let pages = Array(0..<max(0, pageCount))
        return direction == .rightToLeft ? pages.reversed() : pages
    }

    /// Where an up (`forward: false`) or down (`forward: true`) press moves
    /// focus from `page`.
    public static func jump(from page: Int, forward: Bool, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let target = page + (forward ? jumpSize : -jumpSize)
        return min(pageCount - 1, max(0, target))
    }

    /// The page a left or right press moves focus to, following the
    /// reading direction. Nil past either end.
    public static func neighbor(of page: Int, screen: ScreenDirection, direction: ReadingDirection,
                                pageCount: Int) -> Int? {
        let target = page + (direction.isForward(screen) ? 1 : -1)
        return (0..<pageCount).contains(target) ? target : nil
    }

    /// How far through the chapter `page` is, 0...1, for the progress bar.
    /// The last page is 1.
    public static func progress(page: Int, pageCount: Int) -> Double {
        guard pageCount > 1 else { return pageCount == 1 ? 1 : 0 }
        return Double(min(max(0, page), pageCount - 1)) / Double(pageCount - 1)
    }

    /// "Page 12 of 40".
    public static func label(page: Int, pageCount: Int) -> String {
        guard pageCount > 0 else { return "" }
        return "Page \(min(max(0, page), pageCount - 1) + 1) of \(pageCount)"
    }

    /// Thumbnail width for a given height, from the page's aspect ratio
    /// (placeholder aspect until its size is known). Wide pages are capped
    /// at two page widths so a panorama doesn't fill the strip.
    public static func thumbnailWidth(height: Double, size: PageSize?) -> Double {
        let aspect = min(SpreadGeometry.aspect(size), SpreadGeometry.placeholderAspect * 2)
        return (height * aspect).rounded()
    }
}
