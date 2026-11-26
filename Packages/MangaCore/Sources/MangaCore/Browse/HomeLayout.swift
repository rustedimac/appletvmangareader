import Foundation

/// A kind of row on the Home screen. Favorites and Caught Up are one row
/// each; the server feeds get one row per server.
public enum HomeRowKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case continueReading
    case favorites
    case recentlyUpdated
    case newlyAdded
    case caughtUp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .continueReading: return HomeFeed.continueReading.title
        case .favorites: return "Favorites"
        case .recentlyUpdated: return HomeFeed.recentlyUpdated.title
        case .newlyAdded: return HomeFeed.newlyAdded.title
        case .caughtUp: return "Caught Up"
        }
    }

    /// The server feed behind this row, or nil for rows kept on the device.
    public var feed: HomeFeed? {
        switch self {
        case .continueReading: return .continueReading
        case .recentlyUpdated: return .recentlyUpdated
        case .newlyAdded: return .newlyAdded
        case .favorites, .caughtUp: return nil
        }
    }
}

/// How Home shows the server feeds (Continue Reading, Recently Updated,
/// Newly Added) when there are several servers.
public enum HomeServerRows: String, Codable, CaseIterable, Sendable, Identifiable {
    /// One row per feed with every server's series merged in the feed's
    /// order (`HomeMerge`). The default.
    case merged
    /// One row per feed and server ("Newly Added · Kavita").
    case perServer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .merged: return "All in One Row"
        case .perServer: return "Row per Server"
        }
    }
}

/// Where a poster names its server, in rows and grids that mix servers.
public enum PosterServerLabel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// After the poster's caption, on the same line, or on its own line.
    case underTitle
    /// A small tag in the top-left corner of the cover.
    case onCover
    case off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .underTitle: return "Under Title"
        case .onCover: return "On Cover"
        case .off: return "Off"
        }
    }
}

/// The order of Home rows, which are hidden, and how servers are shown,
/// per profile.
public struct HomeLayout: Codable, Hashable, Sendable {
    /// Rows in display order. Kinds missing here (added in a later
    /// version) are put back in their default place by `rows`.
    public var order: [HomeRowKind]
    public var hidden: Set<HomeRowKind>
    /// Merged rows (default) or one row per server.
    public var serverRows: HomeServerRows
    /// Where posters name their server when a row or grid mixes servers.
    public var serverLabel: PosterServerLabel

    public static let defaultOrder: [HomeRowKind] = [.continueReading, .favorites, .recentlyUpdated, .newlyAdded, .caughtUp]
    public static let `default` = HomeLayout()

    public init(order: [HomeRowKind] = HomeLayout.defaultOrder, hidden: Set<HomeRowKind> = [],
                serverRows: HomeServerRows = .merged, serverLabel: PosterServerLabel = .underTitle) {
        self.order = order
        self.hidden = hidden
        self.serverRows = serverRows
        self.serverLabel = serverLabel
    }

    private enum CodingKeys: String, CodingKey { case order, hidden, serverRows, serverLabel }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown kinds (from a newer version) are dropped, not fatal.
        let rawOrder = (try? c.decodeIfPresent([String].self, forKey: .order)) ?? nil
        let rawHidden = (try? c.decodeIfPresent([String].self, forKey: .hidden)) ?? nil
        order = rawOrder?.compactMap(HomeRowKind.init(rawValue:)) ?? HomeLayout.defaultOrder
        hidden = Set(rawHidden?.compactMap(HomeRowKind.init(rawValue:)) ?? [])
        // Layouts saved before these options existed get the defaults:
        // merged rows, server name under the title.
        serverRows = ((try? c.decodeIfPresent(String.self, forKey: .serverRows)) ?? nil)
            .flatMap(HomeServerRows.init(rawValue:)) ?? .merged
        serverLabel = ((try? c.decodeIfPresent(String.self, forKey: .serverLabel)) ?? nil)
            .flatMap(PosterServerLabel.init(rawValue:)) ?? .underTitle
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
        if serverRows != .merged { try c.encode(serverRows.rawValue, forKey: .serverRows) }
        if serverLabel != .underTitle { try c.encode(serverLabel.rawValue, forKey: .serverLabel) }
    }

    /// Puts the rows back in the default order, all shown. Keeps the
    /// server options.
    public mutating func resetRows() {
        order = HomeLayout.defaultOrder
        hidden = []
    }

    /// Whether the rows are in the default order and all shown.
    public var rowsAreDefault: Bool { rows == HomeLayout.defaultOrder && hidden.isEmpty }

    /// Every kind once, in display order (hidden ones included). Kinds
    /// missing from `order` go back after the kind that precedes them in
    /// the default order.
    public var rows: [HomeRowKind] {
        var result: [HomeRowKind] = []
        for kind in order where !result.contains(kind) { result.append(kind) }
        for (i, kind) in HomeLayout.defaultOrder.enumerated() where !result.contains(kind) {
            let previous = HomeLayout.defaultOrder[..<i].last { result.contains($0) }
            let at = previous.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(kind, at: at)
        }
        return result
    }

    /// The rows to show, in order.
    public var visibleRows: [HomeRowKind] { rows.filter { !hidden.contains($0) } }

    public func isHidden(_ kind: HomeRowKind) -> Bool { hidden.contains(kind) }

    public mutating func setHidden(_ kind: HomeRowKind, _ isHidden: Bool) {
        if isHidden { hidden.insert(kind) } else { hidden.remove(kind) }
    }

    public func canMove(_ kind: HomeRowKind, by offset: Int) -> Bool {
        guard let i = rows.firstIndex(of: kind) else { return false }
        return rows.indices.contains(i + offset) && offset != 0
    }

    /// Moves a row up (negative) or down (positive), clamped to the ends.
    public mutating func move(_ kind: HomeRowKind, by offset: Int) {
        var current = rows
        guard let i = current.firstIndex(of: kind) else { return }
        let target = min(max(0, i + offset), current.count - 1)
        guard target != i else { return }
        current.remove(at: i)
        current.insert(kind, at: target)
        order = current
    }

    public var isDefault: Bool { rowsAreDefault && serverRows == .merged && serverLabel == .underTitle }
}

/// A series the profile has read to the end, for the Caught Up row.
public struct CaughtUpEntry: Codable, Hashable, Identifiable, Sendable {
    public var series: SeriesSummary
    public var chapterCount: Int
    public var caughtUpAt: Date

    public var id: SeriesRef { series.ref }

    public init(series: SeriesSummary, chapterCount: Int, caughtUpAt: Date) {
        self.series = series
        self.chapterCount = chapterCount
        self.caughtUpAt = caughtUpAt
    }

    private enum CodingKeys: String, CodingKey { case series, chapterCount, caughtUpAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        series = try c.decode(SeriesSummary.self, forKey: .series)
        // Zero means "caught up with whatever there is".
        chapterCount = c.tolerant(.chapterCount, default: 0)
        caughtUpAt = c.tolerant(.caughtUpAt, default: .distantPast)
    }
}

/// Browsing preferences for one profile: Home layout, library sorts and
/// reading styles, poster size, and the Home rows the app keeps itself.
public struct BrowsePreferences: Codable, Hashable, Sendable {
    public var home: HomeLayout
    public var gridDensity: GridDensity
    /// What posters show under the title.
    public var posterCaption: PosterCaption
    /// Shows "40%" next to poster progress bars. On by default.
    public var showsProgressPercent: Bool
    /// The app's look outside the reader.
    public var theme: AppTheme
    /// Keyed by `LibraryKey.storageKey`.
    public var libraries: [String: LibraryOptions]
    /// Sort, grid order and filter for libraries without their own.
    public var libraryDefaults: LibraryDefaults
    /// Series removed from Continue Reading, keyed by `SeriesRef.storageKey`,
    /// with when. A series comes back once it's read again after that.
    public var dismissedContinueReading: [String: Date]
    /// Newest first, at most `caughtUpLimit`.
    public var caughtUp: [CaughtUpEntry]

    /// Keeps AppState small (tvOS UserDefaults is about 1 MB).
    public static let caughtUpLimit = 30
    public static let dismissedLimit = 100

    public init(home: HomeLayout = .default, gridDensity: GridDensity = .default,
                posterCaption: PosterCaption = .default, showsProgressPercent: Bool = true, theme: AppTheme = .default, libraries: [String: LibraryOptions] = [:], dismissedContinueReading: [String: Date] = [:],
                caughtUp: [CaughtUpEntry] = [], libraryDefaults: LibraryDefaults = .default) {
        self.home = home
        self.libraryDefaults = libraryDefaults
        self.gridDensity = gridDensity
        self.posterCaption = posterCaption
        self.showsProgressPercent = showsProgressPercent
        self.theme = theme
        self.libraries = libraries
        self.dismissedContinueReading = dismissedContinueReading
        self.caughtUp = caughtUp
    }

    private enum CodingKeys: String, CodingKey { case home, gridDensity, posterCaption, showsProgressPercent, theme, libraries, dismissedContinueReading, caughtUp, libraryDefaults }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        home = (try? c.decodeIfPresent(HomeLayout.self, forKey: .home)) ?? .default
        gridDensity = (try? c.decodeIfPresent(GridDensity.self, forKey: .gridDensity)) ?? .default
        posterCaption = (try? c.decodeIfPresent(PosterCaption.self, forKey: .posterCaption)) ?? .default
        showsProgressPercent = (try? c.decodeIfPresent(Bool.self, forKey: .showsProgressPercent)) ?? true
        theme = (try? c.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? .default
        // One unreadable entry costs that entry, not the list.
        libraries = c.tolerantDictionary(.libraries)
        dismissedContinueReading = c.tolerantDictionary(.dismissedContinueReading)
        caughtUp = c.tolerantArray(.caughtUp)
        libraryDefaults = (try? c.decodeIfPresent(LibraryDefaults.self, forKey: .libraryDefaults)) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !home.isDefault { try c.encode(home, forKey: .home) }
        if gridDensity != .default { try c.encode(gridDensity, forKey: .gridDensity) }
        if posterCaption != .default { try c.encode(posterCaption, forKey: .posterCaption) }
        if !showsProgressPercent { try c.encode(showsProgressPercent, forKey: .showsProgressPercent) }
        if theme != .default { try c.encode(theme, forKey: .theme) }
        if !libraries.isEmpty { try c.encode(libraries, forKey: .libraries) }
        if !dismissedContinueReading.isEmpty { try c.encode(dismissedContinueReading, forKey: .dismissedContinueReading) }
        if !caughtUp.isEmpty { try c.encode(caughtUp, forKey: .caughtUp) }
        if !libraryDefaults.isDefault { try c.encode(libraryDefaults, forKey: .libraryDefaults) }
    }

    public func options(for key: LibraryKey) -> LibraryOptions {
        libraries[key.storageKey] ?? LibraryOptions()
    }

    /// The library's own options with unset sort, grid order and filter
    /// taken from `libraryDefaults`.
    public func resolvedOptions(for key: LibraryKey) -> LibraryOptions {
        options(for: key).resolved(with: libraryDefaults)
    }

    public mutating func setOptions(_ options: LibraryOptions, for key: LibraryKey) {
        libraries[key.storageKey] = options.isEmpty ? nil : options
    }

    /// The reading style of the first of `series`' libraries/categories
    /// that has one.
    public func readingStyle(for series: SeriesSummary) -> LibraryReadingStyle? {
        for id in series.memberCategoryIDs ?? [] {
            if let style = libraries[LibraryKey(serverID: series.ref.serverID, categoryID: id).storageKey]?.readingStyle {
                return style
            }
        }
        return nil
    }

    // MARK: Continue Reading

    public mutating func dismissFromContinueReading(_ ref: SeriesRef, at now: Date) {
        dismissedContinueReading[ref.storageKey] = now
        if dismissedContinueReading.count > Self.dismissedLimit,
           let oldest = dismissedContinueReading.min(by: { $0.value < $1.value })?.key {
            dismissedContinueReading[oldest] = nil
        }
    }

    /// Drops dismissed series, unless `readSince` says they were read
    /// after being dismissed.
    public func filterContinueReading(_ series: [SeriesSummary], lastRead: (SeriesRef) -> Date?) -> [SeriesSummary] {
        series.filter { s in
            guard let dismissed = dismissedContinueReading[s.ref.storageKey] else { return true }
            guard let read = lastRead(s.ref) else { return false }
            return read > dismissed
        }
    }

    // MARK: Caught Up

    /// Updates the Caught Up row from a freshly loaded series: in it when
    /// every chapter is read, out of it otherwise.
    public mutating func noteCaughtUp(_ detail: SeriesDetail, summary: SeriesSummary? = nil, now: Date) {
        let ref = detail.summary.ref
        let isCaughtUp = !detail.chapters.isEmpty && detail.chapters.allSatisfy(\.isRead)
        let existing = caughtUp.first { $0.series.ref == ref }
        guard isCaughtUp else {
            if existing != nil { caughtUp.removeAll { $0.series.ref == ref } }
            return
        }
        var series = summary ?? detail.summary
        series.unreadCount = 0
        if let existing, existing.chapterCount == detail.chapters.count, existing.series == series { return }
        caughtUp.removeAll { $0.series.ref == ref }
        let date = existing?.chapterCount == detail.chapters.count ? existing!.caughtUpAt : now
        caughtUp.append(CaughtUpEntry(series: series, chapterCount: detail.chapters.count, caughtUpAt: date))
        caughtUp.sort { $0.caughtUpAt > $1.caughtUpAt }
        if caughtUp.count > Self.caughtUpLimit { caughtUp.removeLast(caughtUp.count - Self.caughtUpLimit) }
    }

    /// Drops Caught Up series that a server feed shows with unread
    /// chapters again. Returns true if anything changed.
    @discardableResult
    public mutating func pruneCaughtUp(seenIn feeds: [SeriesSummary]) -> Bool {
        let unread = Set(feeds.filter { ($0.unreadCount ?? 0) > 0 }.map(\.ref))
        let before = caughtUp.count
        caughtUp.removeAll { unread.contains($0.series.ref) }
        return caughtUp.count != before
    }

    /// Removes everything that belongs to a server.
    public mutating func removeServer(_ id: UUID) {
        let prefix = id.uuidString + "|"
        libraries = libraries.filter { !$0.key.hasPrefix(prefix) }
        dismissedContinueReading = dismissedContinueReading.filter { !$0.key.hasPrefix(prefix) }
        caughtUp.removeAll { $0.series.ref.serverID == id }
    }

    public var isDefault: Bool { self == BrowsePreferences() }
}
