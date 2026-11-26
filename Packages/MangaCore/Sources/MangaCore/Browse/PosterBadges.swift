import Foundation

/// What a poster shows besides its cover: a corner badge (unread chapters
/// or a check when finished), a progress bar, and a caption with the size
/// of the series.
public struct PosterBadges: Equatable, Sendable {
    public enum Corner: Equatable, Sendable {
        case none
        case unread(Int)
        case finished
    }

    public var corner: Corner
    /// Fraction read, only while partway (0 < progress < 1). Drawn on the
    /// cover.
    public var progress: Double?
    /// "45 chapters" or "320 pages" under the title, per `PosterCaption`.
    public var caption: String?
    /// Fraction read (0...1) for the bar under the title, only with the
    /// `.progress` caption and when the server says how much was read.
    public var titleProgress: Double?

    public init(corner: Corner = .none, progress: Double? = nil, caption: String? = nil,
                titleProgress: Double? = nil) {
        self.corner = corner
        self.progress = progress
        self.caption = caption
        self.titleProgress = titleProgress
    }

    /// Kavita reports pages (total and read), so it gets a progress bar
    /// from pages; its `unreadCount` is pages, too big a number for a
    /// badge, so the badge uses `unreadChapters` (fetched per poster). Suwayomi library grids report chapters, so they get the
    /// unread chapter count. Anything else falls back to `unreadCount`.
    /// `style` picks what goes under the title.
    public init(series: SeriesSummary, caption style: PosterCaption = .default) {
        let fraction: Double?
        if let pages = series.pageCount, pages > 0, let read = series.pagesRead {
            fraction = min(1, max(0, Double(read) / Double(pages)))
            // The badge counts chapters, like every other server's.
            let corner: Corner
            if read >= pages {
                corner = .finished
            } else if let unread = series.unreadChapters, unread > 0 {
                corner = .unread(unread)
            } else {
                corner = .none
            }
            self.init(corner: corner, progress: Self.partial(fraction!))
        } else if let chapters = series.chapterCount, chapters > 0, let unread = series.unreadCount {
            let read = max(0, chapters - unread)
            fraction = min(1, Double(read) / Double(chapters))
            self.init(corner: unread <= 0 ? .finished : .unread(unread), progress: Self.partial(fraction!))
        } else if let unread = series.unreadCount, unread > 0 {
            fraction = nil
            self.init(corner: .unread(unread))
        } else {
            fraction = nil
            self.init()
        }
        switch style {
        case .chapters:
            caption = Self.chapterCaption(series)
        case .pages:
            if let pages = series.pageCount, pages > 0 {
                caption = Self.count(pages, "page")
            } else {
                caption = Self.chapterCaption(series)
            }
        case .progress:
            titleProgress = fraction
        case .off:
            break
        }
    }

    static func chapterCaption(_ series: SeriesSummary) -> String? {
        guard let chapters = series.chapterCount, chapters > 0 else { return nil }
        return count(chapters, (series.countUnit ?? .chapter).noun)
    }

    /// For VoiceOver, e.g. "12 unread, 40 percent read".
    public var accessibilityValue: String {
        var parts: [String] = []
        switch corner {
        case .unread(let n): parts.append("\(n) unread")
        case .finished: parts.append("finished")
        case .none: break
        }
        if let read = progress ?? titleProgress { parts.append("\(Int((read * 100).rounded())) percent read") }
        if let caption { parts.append(caption) }
        return parts.joined(separator: ", ")
    }

    /// How much of the series is read (0...1), measured the way its poster
    /// measures it: pages when the listing reports them (Kavita), else
    /// chapters. Nil when the server says neither.
    public static func readFraction(_ series: SeriesSummary) -> Double? {
        if let pages = series.pageCount, pages > 0, let read = series.pagesRead {
            return min(1, max(0, Double(read) / Double(pages)))
        }
        if let chapters = series.chapterCount, chapters > 0, let unread = series.unreadCount {
            return min(1, Double(max(0, chapters - unread)) / Double(chapters))
        }
        return nil
    }

    /// "42% read" for the series page, from its loaded chapters, so it
    /// agrees with the series' poster and changes as soon as the page
    /// reloads after reading. Nil for a series with no chapters.
    public static func readText(detail: SeriesDetail, summary: SeriesSummary) -> String? {
        guard !detail.chapters.isEmpty else { return nil }
        let current = SeriesProgressOverride(detail: detail).applied(to: summary)
        return readFraction(current).map { "\(percentText($0)) read" }
    }

    /// "40%" next to a progress bar. Never "0%" once something is read or
    /// "100%" before the end, so the number agrees with the bar and badge.
    public static func percentText(_ fraction: Double) -> String {
        let f = min(1, max(0, fraction))
        var percent = Int((f * 100).rounded())
        if f > 0, percent == 0 { percent = 1 }
        if f < 1, percent == 100 { percent = 99 }
        return "\(percent)%"
    }

    static func partial(_ fraction: Double) -> Double? {
        fraction > 0 && fraction < 1 ? fraction : nil
    }

    static func count(_ n: Int, _ noun: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        let number = formatter.string(from: NSNumber(value: n)) ?? String(n)
        return "\(number) \(noun)\(n == 1 ? "" : "s")"
    }
}
