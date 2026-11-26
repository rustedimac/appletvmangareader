import Foundation

/// A bookmarked page, kept per profile. Stores enough about the series and
/// chapter to list and open it without asking the server first.
public struct Bookmark: Codable, Hashable, Identifiable, Sendable {
    public var series: SeriesSummary
    public var chapterID: String
    /// Kavita volume id, needed by Kavita's bookmark API. Nil for Suwayomi.
    public var volumeID: String?
    public var chapterTitle: String
    /// The chapter's reading-order position (`Chapter.number`). Nil for a
    /// bookmark imported from the server before its series was opened.
    public var chapterNumber: Double?
    /// Zero-based page within the chapter.
    public var page: Int
    public var createdAt: Date
    /// True until the server confirms it has this bookmark. Bookmarks start
    /// out this way, so if a profile turns on server sync later, the ones it
    /// made while local are uploaded instead of dropped.
    public var needsUpload: Bool

    public var id: String { Bookmark.id(series: series.ref, chapterID: chapterID, page: page) }

    public static func id(series: SeriesRef, chapterID: String, page: Int) -> String {
        "\(series.storageKey)|\(chapterID)|\(page)"
    }

    public init(series: SeriesSummary, chapterID: String, volumeID: String? = nil, chapterTitle: String,
                chapterNumber: Double? = nil, page: Int, createdAt: Date = Date(), needsUpload: Bool = true) {
        self.series = series
        self.chapterID = chapterID
        self.volumeID = volumeID
        self.chapterTitle = chapterTitle
        self.chapterNumber = chapterNumber
        self.page = max(0, page)
        self.createdAt = createdAt
        self.needsUpload = needsUpload
    }

    public init(series: SeriesSummary, chapter: Chapter, page: Int, createdAt: Date = Date()) {
        self.init(series: series, chapterID: chapter.id, volumeID: chapter.volumeID, chapterTitle: chapter.title,
                  chapterNumber: chapter.number, page: page, createdAt: createdAt)
    }

    /// One-based page for display.
    public var pageLabel: String { "Page \(page + 1)" }

    private enum CodingKeys: String, CodingKey {
        case series, chapterID, volumeID, chapterTitle, chapterNumber, page, createdAt, needsUpload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        series = try c.decode(SeriesSummary.self, forKey: .series)
        chapterID = try c.decode(String.self, forKey: .chapterID)
        volumeID = c.tolerant(.volumeID)
        chapterTitle = c.tolerant(.chapterTitle, default: "")
        chapterNumber = c.tolerant(.chapterNumber)
        page = try c.decode(Int.self, forKey: .page)
        createdAt = c.tolerant(.createdAt, default: .distantPast)
        needsUpload = c.tolerant(.needsUpload, default: false)
    }

    // Skip empty fields to keep AppState small.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(series, forKey: .series)
        try c.encode(chapterID, forKey: .chapterID)
        try c.encodeIfPresent(volumeID, forKey: .volumeID)
        try c.encode(chapterTitle, forKey: .chapterTitle)
        try c.encodeIfPresent(chapterNumber, forKey: .chapterNumber)
        try c.encode(page, forKey: .page)
        try c.encode(createdAt, forKey: .createdAt)
        if needsUpload { try c.encode(true, forKey: .needsUpload) }
    }
}

/// How finely a server stores bookmarks.
public enum BookmarkGranularity: Sendable {
    /// Kavita bookmarks individual pages.
    case page
    /// Suwayomi (like Mihon) bookmarks whole chapters.
    case chapter
}

/// A bookmark as a server reports it.
public struct ServerBookmark: Hashable, Sendable {
    public var seriesID: String
    public var chapterID: String
    public var volumeID: String?
    /// Zero-based page. Nil when the server bookmarks whole chapters.
    public var page: Int?
    public var chapterTitle: String?
    /// The series, when the server includes it (lists across series).
    public var series: SeriesSummary?

    public init(seriesID: String, chapterID: String, volumeID: String? = nil, page: Int?,
                chapterTitle: String? = nil, series: SeriesSummary? = nil) {
        self.seriesID = seriesID
        self.chapterID = chapterID
        self.volumeID = volumeID
        self.page = page
        self.chapterTitle = chapterTitle
        self.series = series
    }
}

/// A server that can store bookmarks for the signed-in user. Kavita and
/// Suwayomi implement it; the app keeps bookmarks locally either way and
/// syncs through this when the profile syncs to the server
/// (`ProfileServerSettings.syncProgressToServer`).
public protocol BookmarkSyncing: MangaServer {
    var bookmarkGranularity: BookmarkGranularity { get }
    /// Bookmarks in one series.
    func bookmarks(seriesID: String) async throws -> [ServerBookmark]
    /// Every bookmark the user has on this server, with `series` filled in.
    func allBookmarks() async throws -> [ServerBookmark]
    /// Adds or removes a bookmark. Chapter-granularity servers ignore the page.
    func setBookmark(_ bookmarked: Bool, _ bookmark: Bookmark) async throws
}

/// Pure rules for reconciling local bookmarks with a server's.
public enum BookmarkSync {
    /// Merges what the server reported with the profile's local bookmarks in
    /// the same scope (one series, or everything on one server).
    ///
    /// The server is the source of truth for bookmarks it has confirmed: a
    /// confirmed bookmark that is gone from the server was removed somewhere
    /// else and is dropped. Bookmarks still waiting to upload are kept.
    ///
    /// - Page servers: every server bookmark is kept, reusing the local copy
    ///   (chapter title, number, date) when there is one.
    /// - Chapter servers: local page bookmarks in a bookmarked chapter are
    ///   kept; a bookmarked chapter with none gets one on its first page.
    ///
    /// - Parameter series: the series for a server bookmark that doesn't
    ///   carry one (lookups by series id). Bookmarks with no series are skipped.
    public static func merge(local: [Bookmark], server: [ServerBookmark], granularity: BookmarkGranularity,
                             series: (String) -> SeriesSummary? = { _ in nil }, now: Date = Date()) -> [Bookmark] {
        var result: [Bookmark] = []
        var seen = Set<String>()
        func makeFromServer(_ s: ServerBookmark, page: Int, summary: SeriesSummary?) -> Bookmark? {
            guard let summary = summary ?? local.first(where: { $0.series.ref.seriesID == s.seriesID })?.series
            else { return nil }
            return Bookmark(series: summary, chapterID: s.chapterID, volumeID: s.volumeID,
                            chapterTitle: s.chapterTitle ?? "", page: page, createdAt: now, needsUpload: false)
        }

        switch granularity {
        case .page:
            for s in server {
                let page = s.page ?? 0
                if var existing = local.first(where: { $0.series.ref.seriesID == s.seriesID && $0.chapterID == s.chapterID && $0.page == page }) {
                    existing.needsUpload = false
                    if existing.volumeID == nil { existing.volumeID = s.volumeID }
                    if seen.insert(existing.id).inserted { result.append(existing) }
                } else if let b = makeFromServer(s, page: page, summary: s.series ?? series(s.seriesID)),
                          seen.insert(b.id).inserted {
                    result.append(b)
                }
            }
        case .chapter:
            let bookmarkedChapters = Set(server.map { "\($0.seriesID)|\($0.chapterID)" })
            func key(_ b: Bookmark) -> String { "\(b.series.ref.seriesID)|\(b.chapterID)" }
            for var b in local where bookmarkedChapters.contains(key(b)) {
                b.needsUpload = false
                if seen.insert(b.id).inserted { result.append(b) }
            }
            var covered = Set(result.map(key))
            for s in server where covered.insert("\(s.seriesID)|\(s.chapterID)").inserted {
                if let b = makeFromServer(s, page: s.page ?? 0, summary: s.series ?? series(s.seriesID)),
                   seen.insert(b.id).inserted {
                    result.append(b)
                }
            }
        }
        for b in local where b.needsUpload && seen.insert(b.id).inserted { result.append(b) }
        return result
    }

    /// Whether removing `removed` should be sent to the server. A chapter
    /// server only drops the chapter's bookmark once no page in it is left.
    public static func shouldSendRemoval(of removed: Bookmark, remaining: [Bookmark],
                                         granularity: BookmarkGranularity) -> Bool {
        switch granularity {
        case .page: return true
        case .chapter:
            return !remaining.contains { $0.series.ref == removed.series.ref && $0.chapterID == removed.chapterID }
        }
    }

    /// Whether adding `added` needs a call: a chapter server already has the
    /// chapter bookmarked when another confirmed page in it is.
    public static func shouldSendAddition(of added: Bookmark, existing: [Bookmark],
                                          granularity: BookmarkGranularity) -> Bool {
        switch granularity {
        case .page: return true
        case .chapter:
            return !existing.contains {
                $0.id != added.id && !$0.needsUpload && $0.series.ref == added.series.ref && $0.chapterID == added.chapterID
            }
        }
    }
}

public extension AppState {
    /// Every bookmark of a profile, newest first.
    func bookmarks(profile: UUID) -> [Bookmark] {
        (profileData[profile.uuidString]?.bookmarks ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// One series' bookmarks in reading order: by chapter, then page.
    /// Bookmarks whose chapter position isn't known yet come last.
    func bookmarks(for ref: SeriesRef, profile: UUID) -> [Bookmark] {
        (profileData[profile.uuidString]?.bookmarks ?? [])
            .filter { $0.series.ref == ref }
            .sorted { a, b in
                switch (a.chapterNumber, b.chapterNumber) {
                case let (x?, y?) where x != y: return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default:
                    if a.chapterID != b.chapterID { return a.createdAt < b.createdAt }
                    return a.page < b.page
                }
            }
    }

    func isBookmarked(_ ref: SeriesRef, chapterID: String, page: Int, profile: UUID) -> Bool {
        let id = Bookmark.id(series: ref, chapterID: chapterID, page: page)
        return profileData[profile.uuidString]?.bookmarks.contains { $0.id == id } ?? false
    }

    /// Adds or removes a bookmark. Adding one that exists keeps the original.
    mutating func setBookmark(_ bookmark: Bookmark, _ on: Bool, profile: UUID) {
        mutateData(profile) { data in
            if on {
                if !data.bookmarks.contains(where: { $0.id == bookmark.id }) { data.bookmarks.append(bookmark) }
            } else {
                data.bookmarks.removeAll { $0.id == bookmark.id }
            }
        }
    }

    /// Replaces the bookmarks that match `scope` with `merged`.
    mutating func replaceBookmarks(where scope: (Bookmark) -> Bool, with merged: [Bookmark], profile: UUID) {
        mutateData(profile) { data in
            data.bookmarks.removeAll(where: scope)
            let ids = Set(data.bookmarks.map(\.id))
            data.bookmarks += merged.filter { !ids.contains($0.id) }
        }
    }

    /// Notes that the server now has these bookmarks.
    mutating func markBookmarksUploaded(_ ids: Set<String>, profile: UUID) {
        mutateData(profile) { data in
            for i in data.bookmarks.indices where ids.contains(data.bookmarks[i].id) {
                data.bookmarks[i].needsUpload = false
            }
        }
    }

    /// Fills in chapter titles, positions and volume ids from a freshly
    /// loaded series, for bookmarks imported from the server.
    mutating func updateBookmarkChapters(from detail: SeriesDetail, profile: UUID) {
        let byID = Dictionary(detail.chapters.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ref = detail.summary.ref
        guard profileData[profile.uuidString]?.bookmarks.contains(where: { $0.series.ref == ref }) == true else { return }
        mutateData(profile) { data in
            for i in data.bookmarks.indices where data.bookmarks[i].series.ref == ref {
                guard let chapter = byID[data.bookmarks[i].chapterID] else { continue }
                data.bookmarks[i].chapterTitle = chapter.title
                data.bookmarks[i].chapterNumber = chapter.number
                data.bookmarks[i].volumeID = data.bookmarks[i].volumeID ?? chapter.volumeID
            }
        }
    }
}
