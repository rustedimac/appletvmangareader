import Foundation

/// What a poster shows under its title (Library, Home, Favorites, Search).
/// A profile setting, synced with the rest of `BrowsePreferences`.
public enum PosterCaption: String, Codable, CaseIterable, Sendable, Identifiable {
    /// "42 chapters" (or volumes or books, in the server's own unit).
    case chapters
    /// "1,383 pages". Servers that don't report pages show chapters.
    case pages
    /// A thin reading-progress bar.
    case progress
    /// Just the title.
    case off

    public static let `default` = PosterCaption.chapters

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chapters: return "Chapters"
        case .pages: return "Pages"
        case .progress: return "Progress Bar"
        case .off: return "Off"
        }
    }

    /// Settings footer, shared by Customize Home and Sort & View.
    public static let footnote = "Chapters shows volumes or books where the server counts those. Servers that don't report pages show chapters instead. Applies everywhere posters appear."

    /// Whether this caption needs a chapter count the library listing may
    /// not include (see `MangaServer.chapterCount(seriesID:)`).
    public func needsChapterCount(_ series: SeriesSummary) -> Bool {
        guard series.chapterCount == nil else { return false }
        switch self {
        case .chapters: return true
        case .pages: return (series.pageCount ?? 0) <= 0
        case .progress, .off: return series.needsUnreadChapters
        }
    }
}

/// The unit a series is counted in. Kavita series made of volume files
/// count volumes, ebook and PDF series count books, Komga counts books.
public enum SeriesCountUnit: String, Codable, Sendable {
    case chapter
    case volume
    case book

    public var noun: String { rawValue }
}

/// A series' size: how many chapters (or volumes or books) it has.
public struct SeriesCount: Codable, Hashable, Sendable {
    public var count: Int
    public var unit: SeriesCountUnit
    /// How many of them are unread, when the server said (for the unread
    /// badge on posters whose listing reports pages).
    public var unread: Int?

    public init(count: Int, unit: SeriesCountUnit = .chapter, unread: Int? = nil) {
        self.count = count
        self.unit = unit
        self.unread = unread
    }

    /// Counts a chapter list: books when every entry opens in the book
    /// reader or is a PDF, chapters otherwise.
    public init(chapters: [Chapter], seriesFormat: ContentFormat? = nil) {
        let formats = chapters.map { $0.format ?? seriesFormat }
        let books = !formats.isEmpty && formats.allSatisfy { $0?.isText == true || $0 == .pdf }
        self.init(count: chapters.count, unit: books ? .book : .chapter,
                  unread: chapters.filter { !$0.isRead }.count)
    }
}

public extension SeriesSummary {
    /// The series with `count` filled in where the listing left it out.
    /// A series whose listing reports pages (Kavita) and that isn't
    /// finished needs its unread chapter count fetched for the poster's
    /// unread badge, whatever the caption shows.
    var needsUnreadChapters: Bool {
        guard unreadChapters == nil, let pages = pageCount, pages > 0, let read = pagesRead else { return false }
        return read < pages
    }

    func withCount(_ count: SeriesCount?) -> SeriesSummary {
        guard let count else { return self }
        var s = self
        if s.unreadChapters == nil, pageCount != nil { s.unreadChapters = count.unread }
        guard chapterCount == nil else { return s }
        s.chapterCount = count.count
        s.countUnit = count.unit
        return s
    }
}
