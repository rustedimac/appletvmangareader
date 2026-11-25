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
    /// Fraction read, only while partway (0 < progress < 1).
    public var progress: Double?
    /// "320 pages" or "45 chapters", when known.
    public var caption: String?

    public init(corner: Corner = .none, progress: Double? = nil, caption: String? = nil) {
        self.corner = corner
        self.progress = progress
        self.caption = caption
    }

    /// Kavita reports pages (total and read), so it gets a progress bar
    /// and a page count; its `unreadCount` is pages, too big a number for
    /// a badge. Suwayomi library grids report chapters, so they get the
    /// unread chapter count. Anything else falls back to `unreadCount`.
    public init(series: SeriesSummary) {
        if let pages = series.pageCount, pages > 0, let read = series.pagesRead {
            let fraction = min(1, max(0, Double(read) / Double(pages)))
            self.init(corner: read >= pages ? .finished : .none,
                      progress: Self.partial(fraction),
                      caption: Self.count(pages, "page"))
        } else if let chapters = series.chapterCount, chapters > 0, let unread = series.unreadCount {
            let read = max(0, chapters - unread)
            self.init(corner: unread <= 0 ? .finished : .unread(unread),
                      progress: Self.partial(Double(read) / Double(chapters)),
                      caption: Self.count(chapters, "chapter"))
        } else if let unread = series.unreadCount, unread > 0 {
            self.init(corner: .unread(unread))
        } else {
            self.init()
        }
    }

    /// For VoiceOver, e.g. "12 unread, 40 percent read".
    public var accessibilityValue: String {
        var parts: [String] = []
        switch corner {
        case .unread(let n): parts.append("\(n) unread")
        case .finished: parts.append("finished")
        case .none: break
        }
        if let progress { parts.append("\(Int((progress * 100).rounded())) percent read") }
        if let caption { parts.append(caption) }
        return parts.joined(separator: ", ")
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
