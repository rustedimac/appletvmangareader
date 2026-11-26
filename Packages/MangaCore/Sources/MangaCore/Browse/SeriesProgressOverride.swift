import Foundation

/// Fresh read progress for one series, taken from its detail after the
/// user reads or marks chapters. Home rows, library grids and Favorites
/// keep the summaries they loaded, so posters lay this on top and show the
/// new badge, bar and percentage without reloading every row.
public struct SeriesProgressOverride: Equatable, Sendable {
    public var unreadCount: Int
    public var chapterCount: Int
    /// Total and read pages, from the chapters, when they all know their
    /// page count. Used only for series whose listing reports pages
    /// (Kavita), so a poster keeps the same kind of progress it had.
    public var pageCount: Int?
    public var pagesRead: Int?

    public init(unreadCount: Int, chapterCount: Int, pageCount: Int? = nil, pagesRead: Int? = nil) {
        self.unreadCount = unreadCount
        self.chapterCount = chapterCount
        self.pageCount = pageCount
        self.pagesRead = pagesRead
    }

    /// From a detail whose chapters already carry this profile's progress
    /// (`AppModel.seriesDetail` resolves local and queued changes).
    public init(detail: SeriesDetail) {
        let chapters = detail.chapters
        let unread = chapters.filter { !$0.isRead }.count
        var pages: Int?
        var read: Int?
        if !chapters.isEmpty, chapters.allSatisfy({ $0.pageCount > 0 }) {
            pages = chapters.reduce(0) { $0 + $1.pageCount }
            read = chapters.reduce(0) { sum, c in
                sum + (c.isRead ? c.pageCount : min(c.pageCount, max(0, c.lastPageRead)))
            }
        }
        self.init(unreadCount: unread, chapterCount: chapters.count, pageCount: pages, pagesRead: read)
    }

    /// `series` with this progress. A listing that reports pages keeps a
    /// page-based bar; one that reports chapters keeps a chapter count.
    public func applied(to series: SeriesSummary) -> SeriesSummary {
        var s = series
        if series.pageCount != nil, series.pagesRead != nil {
            if let pageCount, let pagesRead {
                s.pageCount = pageCount
                s.pagesRead = pagesRead
                s.unreadCount = max(0, pageCount - pagesRead)
                return s
            }
            // Pages unknown now: fall back to chapters.
            s.pagesRead = nil
        }
        s.unreadCount = unreadCount
        // A listing that counts volumes (Kavita) keeps its own count.
        if s.countUnit == nil || s.countUnit == .chapter || s.chapterCount == nil {
            s.chapterCount = chapterCount
        }
        return s
    }
}
