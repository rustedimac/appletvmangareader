import Foundation

/// How a library grid is ordered. Kavita sorts on the server; Suwayomi
/// returns a whole category, so the client sorts it.
public enum LibrarySort: String, Codable, CaseIterable, Sendable, Identifiable {
    case titleAscending
    case titleDescending
    case recentlyAdded
    case recentlyUpdated
    case recentlyRead

    public static let `default` = LibrarySort.titleAscending

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .titleAscending: return "Title A–Z"
        case .titleDescending: return "Title Z–A"
        case .recentlyAdded: return "Recently Added"
        case .recentlyUpdated: return "Recently Updated"
        case .recentlyRead: return "Recently Read"
        }
    }

    /// Title sorts are the ones the A–Z jump bar works with.
    public var isTitleOrder: Bool { self == .titleAscending || self == .titleDescending }
}

/// Poster size in grids (Library and Favorites).
public enum GridDensity: String, Codable, CaseIterable, Sendable, Identifiable {
    /// More posters per row, for big libraries.
    case compact
    case standard
    case large

    public static let `default` = GridDensity.standard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return "Small"
        case .standard: return "Medium"
        case .large: return "Large"
        }
    }

    /// Poster width in points. Height is 1.5×.
    public var posterWidth: Double {
        switch self {
        case .compact: return 170
        case .standard: return 230
        case .large: return 300
        }
    }

    /// Gap between posters in points.
    public var spacing: Double {
        switch self {
        case .compact: return 36
        case .standard: return 48
        case .large: return 56
        }
    }
}

/// The reading style a library or category opens its series in, unless a
/// series has its own settings.
public enum LibraryReadingStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case rightToLeft
    case leftToRight
    case vertical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rightToLeft: return "Right to Left"
        case .leftToRight: return "Left to Right"
        case .vertical: return "Vertical Scroll"
        }
    }

    /// `settings` with this style's mode and direction.
    public func apply(to settings: ReaderSettings) -> ReaderSettings {
        var s = settings
        switch self {
        case .rightToLeft:
            s.mode = .paged
            s.direction = .rightToLeft
        case .leftToRight:
            s.mode = .paged
            s.direction = .leftToRight
        case .vertical:
            s.mode = .webtoon
        }
        return s
    }
}

/// Which way a poster grid fills.
public enum GridOrder: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Right to left when the library reads right to left.
    case automatic
    case leftToRight
    case rightToLeft

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Match Reading Direction"
        case .leftToRight: return "Left to Right"
        case .rightToLeft: return "Right to Left"
        }
    }
}

/// A profile's settings for one library (Kavita) or category (Suwayomi).
/// Nil fields use the profile's `LibraryDefaults` (reading style: the
/// profile's default reader settings); `resolved(with:)` fills them in.
public struct LibraryOptions: Codable, Hashable, Sendable {
    public var sort: LibrarySort?
    /// Nil uses the profile's default reader settings.
    public var readingStyle: LibraryReadingStyle?
    public var gridOrder: GridOrder?
    /// Nil uses the default filter (status and read progress).
    public var filter: LibraryFilter?

    public init(sort: LibrarySort? = nil, readingStyle: LibraryReadingStyle? = nil, gridOrder: GridOrder? = nil,
                filter: LibraryFilter? = nil) {
        self.sort = sort
        self.readingStyle = readingStyle
        self.gridOrder = gridOrder
        self.filter = filter
    }

    public var isEmpty: Bool { sort == nil && readingStyle == nil && gridOrder == nil && filter == nil }

    /// These options with every unset sort, grid order and filter taken
    /// from `defaults`. The reading style stays as it is.
    public func resolved(with defaults: LibraryDefaults) -> LibraryOptions {
        LibraryOptions(sort: sort ?? defaults.sort, readingStyle: readingStyle,
                       gridOrder: gridOrder ?? defaults.gridOrder, filter: filter ?? defaults.filter)
    }

    /// The effective filter (`.empty` when unset and not resolved).
    public var activeFilter: LibraryFilter { filter ?? .empty }

    /// Whether the grid fills right to left: when asked to, or
    /// automatically when the library reads right to left.
    public var gridIsRightToLeft: Bool {
        switch gridOrder ?? .automatic {
        case .automatic: return readingStyle == .rightToLeft
        case .leftToRight: return false
        case .rightToLeft: return true
        }
    }
}

/// Identifies a library or category on a server, for per-library settings.
public struct LibraryKey: Hashable, Sendable {
    public var serverID: UUID
    public var categoryID: String

    public init(serverID: UUID, categoryID: String) {
        self.serverID = serverID
        self.categoryID = categoryID
    }

    public var storageKey: String { "\(serverID.uuidString)|\(categoryID)" }
}

/// The letter index beside a title-sorted grid.
public enum AlphabetIndex {
    /// "#" for digits, symbols and non-Latin titles, then A–Z.
    public static let letters: [String] = ["#"] + (65...90).map { String(UnicodeScalar(UInt8($0))) }

    /// The index letter for a title: its first letter or digit, with
    /// accents removed, and leading quotes or brackets skipped.
    public static func letter(for title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard let first = folded.unicodeScalars.first(where: { CharacterSet.alphanumerics.contains($0) }) else { return "#" }
        let upper = String(first).uppercased()
        if upper.count == 1, let scalar = upper.unicodeScalars.first, (65...90).contains(scalar.value) {
            return upper
        }
        return "#"
    }

    static func rank(_ letter: String) -> Int { letters.firstIndex(of: letter) ?? 0 }

    public enum Jump: Equatable, Sendable {
        /// Scroll to this item.
        case index(Int)
        /// The letter may be on a page that isn't loaded yet.
        case needsMore
        /// Nothing is loaded.
        case none
    }

    /// Where to jump for `letter` in `titles`, which are sorted by title
    /// (`descending` for Z–A). The first title at or past the letter wins,
    /// so a letter with no titles lands on the next one. When the loaded
    /// titles end before the letter and more pages exist, returns
    /// `.needsMore`; when everything is loaded, the last item.
    public static func jump(to letter: String, in titles: [String], descending: Bool = false, hasMore: Bool) -> Jump {
        let target = rank(letter)
        let found = titles.firstIndex { title in
            let r = rank(Self.letter(for: title))
            return descending ? r <= target : r >= target
        }
        if let found { return .index(found) }
        if hasMore { return .needsMore }
        return titles.isEmpty ? .none : .index(titles.count - 1)
    }
}

public extension Array where Element == SeriesSummary {
    /// Sorted by `sort`, for servers that hand back a whole category.
    /// `dates` gives each series' added/updated/read date where known;
    /// series without one go last, by title.
    func sorted(by sort: LibrarySort, dates: [SeriesRef: Date] = [:]) -> [SeriesSummary] {
        func titleOrder(_ a: SeriesSummary, _ b: SeriesSummary) -> Bool {
            a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        switch sort {
        case .titleAscending:
            return self.sorted(by: titleOrder)
        case .titleDescending:
            return self.sorted { titleOrder($1, $0) }
        case .recentlyAdded, .recentlyUpdated, .recentlyRead:
            return self.sorted { a, b in
                switch (dates[a.ref], dates[b.ref]) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return titleOrder(a, b)
                }
            }
        }
    }
}
