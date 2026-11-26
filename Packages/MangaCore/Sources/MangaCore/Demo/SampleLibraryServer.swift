import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An offline server with generated, neutral content. The app uses it for
/// UI tests (`-uiTesting -demoServers`) and SwiftUI previews, so screens
/// can be exercised without a real Kavita or Suwayomi server.
///
/// Series ids are "1"..."seriesCount". Titles cycle through a fixed word
/// list ("Lantern Chronicles 3"), so a search for a word matches every
/// eighth series. Category "all" holds every series; "short" holds the
/// series whose id is a multiple of 3. `categoryScope` limits feeds, search
/// and categories the way the real clients do; `scoped(to:)` makes a copy
/// that shares progress.
public final class SampleLibraryServer: MangaServer, @unchecked Sendable {
    public static let words = ["Ember", "Harbor", "Lantern", "Meadow", "Orbit", "Summit", "Willow", "Zephyr"]

    public let config: ServerConfig
    public let seriesCount: Int
    /// Added before every response, to exercise loading states.
    public let latency: Duration

    /// Library ids to show; nil shows both.
    public let categoryScope: Set<String>?
    /// Thrown by every call when set, to show a server's error state
    /// (`.missingCredential` for "isn't signed in").
    public let failure: MangaError?
    private let store: ProgressStore

    /// Reading progress, shared by every scoped copy of one demo server.
    final class ProgressStore: @unchecked Sendable {
        let lock = NSLock()
        /// chapterID → (zero-based page, completed)
        var progress: [String: (page: Int, completed: Bool)] = [:]
        var lastReadSeries: [String] = []
    }

    public init(config: ServerConfig, seriesCount: Int = 90, latency: Duration = .milliseconds(150),
                categoryScope: Set<String>? = nil, failure: MangaError? = nil) {
        self.config = config
        self.seriesCount = seriesCount
        self.latency = latency
        self.categoryScope = categoryScope
        self.failure = failure
        self.store = ProgressStore()
    }

    private init(copying other: SampleLibraryServer, categoryScope: Set<String>?) {
        config = other.config
        seriesCount = other.seriesCount
        latency = other.latency
        failure = other.failure
        self.categoryScope = categoryScope
        store = other.store
    }

    /// The same server and progress, showing only `scope`.
    public func scoped(to scope: Set<String>?) -> SampleLibraryServer {
        SampleLibraryServer(copying: self, categoryScope: scope)
    }

    /// Marks every chapter of a series read, as if the user had finished
    /// it (UI tests for the Caught Up row).
    public func markAllRead(seriesID: String) {
        guard let n = Int(seriesID), (1...seriesCount).contains(n) else { return }
        store.lock.withLock {
            for c in 1...Self.chapterCount(for: n) { store.progress["\(n)-\(c)"] = (page: 19, completed: true) }
        }
    }

    public static func title(for n: Int) -> String {
        "\(words[(n - 1) % words.count]) Chronicles \(n)"
    }

    public static func chapterCount(for n: Int) -> Int { 3 + n % 12 }

    /// Even series are ongoing, odd ones completed, except every fifth
    /// series is on hiatus and every seventh cancelled.
    public static func status(for n: Int) -> PublicationStatus {
        if n % 7 == 0 { return .cancelled }
        if n % 5 == 0 { return .hiatus }
        return n % 2 == 0 ? .ongoing : .completed
    }

    public static let genreNames = ["Adventure", "Comedy", "Mystery"]

    /// "Demo" plus one of `genreNames`, by id. Multiples of 5 are also
    /// "Horror", for content-filter tests.
    public static func genres(for n: Int) -> [String] {
        [genreNames[n % genreNames.count], "Demo"] + (n % 5 == 0 ? ["Horror"] : [])
    }

    /// Multiples of 6 are tagged "Cliffhanger".
    public static func tags(for n: Int) -> [String] { n % 6 == 0 ? ["Cliffhanger"] : [] }

    /// Age ratings (demo Kavita only): multiples of 7 are Mature 17+,
    /// multiples of 11 unrated, the rest Everyone.
    public static func ageRating(for n: Int) -> AgeRating {
        if n % 7 == 0 { return .mature17Plus }
        if n % 11 == 0 { return .unknown }
        return .everyone
    }

    func summary(_ n: Int) -> SeriesSummary {
        let read = chapters(n).filter(\.isRead).count
        return SeriesSummary(ref: SeriesRef(serverID: config.id, seriesID: String(n)),
                             title: Self.title(for: n), coverURL: nil,
                             unreadCount: Self.chapterCount(for: n) - read, libraryID: "all",
                             categoryIDs: n % 3 == 0 ? ["all", "short"] : ["all"],
                             pageCount: Self.chapterCount(for: n) * 20,
                             chapterCount: Self.chapterCount(for: n))
    }

    func chapters(_ n: Int) -> [Chapter] {
        let ref = SeriesRef(serverID: config.id, seriesID: String(n))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (1...Self.chapterCount(for: n)).map { c in
            let id = "\(n)-\(c)"
            let p = store.lock.withLock { store.progress[id] }
            return Chapter(id: id, seriesRef: ref, title: "Chapter \(c)", number: Double(c), pageCount: 20,
                           lastPageRead: p?.page ?? 0, isRead: p?.completed ?? false,
                           updatedAt: base.addingTimeInterval(Double(n * 1000 + c)))
        }
    }

    func wait() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        if let failure { throw failure }
    }

    private func number(_ seriesID: String) throws -> Int {
        guard let n = Int(seriesID), (1...seriesCount).contains(n) else { throw MangaError.notFound }
        return n
    }

    public func validate() async throws -> String {
        try await wait()
        return "Demo server, \(seriesCount) series"
    }

    public func categories() async throws -> [MangaCategory] {
        try await wait()
        let scope = categoryScope
        return [MangaCategory(id: "all", name: "All Series", order: 0),
                MangaCategory(id: "short", name: "Every Third", order: 1)]
            .filter { scope?.contains($0.id) ?? true }
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: .default)
    }

    /// Title sorts use the titles' natural order (all "Ember" series, then
    /// "Harbor", ...); added and updated are newest id first; read is most
    /// recently read first, then by title.
    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: sort, filter: .empty)
    }

    public var libraryFilterSupport: LibraryFilterSupport { .all }

    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort,
                       filter: LibraryFilter) async throws -> Paged<SeriesSummary> {
        try await wait()
        let inCategory = Array(1...seriesCount).filter { category.id != "short" || $0 % 3 == 0 }
            .filter { n in
                let read = chapters(n).filter(\.isRead).count
                let total = Self.chapterCount(for: n)
                return filter.matches(status: Self.status(for: n), unread: total - read, total: total, genres: Self.genres(for: n))
            }
        let byTitle = inCategory.sorted { Self.title(for: $0).localizedStandardCompare(Self.title(for: $1)) == .orderedAscending }
        let ids: [Int]
        switch sort {
        case .titleAscending: ids = byTitle
        case .titleDescending: ids = byTitle.reversed()
        case .recentlyAdded, .recentlyUpdated: ids = inCategory.sorted(by: >)
        case .recentlyRead:
            let read = store.lock.withLock { store.lastReadSeries }.compactMap { Int($0) }.filter { inCategory.contains($0) }
            ids = read + byTitle.filter { !read.contains($0) }
        }
        let start = max(0, (page - 1) * pageSize)
        guard start < ids.count else { return Paged(items: [], hasMore: false) }
        let end = min(ids.count, start + pageSize)
        return Paged(items: ids[start..<end].map(summary), hasMore: end < ids.count)
    }

    public func filterGenres(in category: MangaCategory) async throws -> [String] {
        try await wait()
        return LibraryFilter.genreList(Self.genreNames + ["Demo"])
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        try await wait()
        let ids: [Int]
        switch feed {
        case .continueReading:
            ids = store.lock.withLock { store.lastReadSeries }.compactMap { Int($0) }
        case .recentlyUpdated:
            ids = Array(stride(from: seriesCount, through: 1, by: -1))
        case .newlyAdded:
            ids = Array(stride(from: seriesCount - 5, through: 1, by: -2))
        }
        return Array(ids.map(summary).scoped(to: categoryScope).prefix(limit))
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        try await wait()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return (1...seriesCount).filter { Self.title(for: $0).lowercased().contains(q) }.map(summary)
            .scoped(to: categoryScope)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        try await wait()
        let n = try number(seriesID)
        return SeriesDetail(summary: summary(n),
                            synopsis: "A generated demo series used to try out the app without a server. Number \(n) of \(seriesCount).",
                            authors: ["Demo Author"], genres: Self.genres(for: n),
                            status: Self.status(for: n).title, chapters: chapters(n))
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        try await wait()
        return (0..<chapter.pageCount).map { i in
            PageDescriptor(index: i, url: config.baseURL.appendingPathComponent("page/\(chapter.id)/\(i).png"),
                           size: PageSize(width: 1000, height: 1500))
        }
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        // Saves take as long as reads, like a real server, so a reload
        // started while a save is in flight sees the old progress.
        try await wait()
        store.lock.withLock {
            store.progress[chapter.id] = (page, completed)
            store.lastReadSeries.removeAll { $0 == chapter.seriesRef.seriesID }
            store.lastReadSeries.insert(chapter.seriesRef.seriesID, at: 0)
        }
    }

    /// Marks the first `read` chapters of every series read and leaves the
    /// next one open at `page`, so UI tests start with progress to undo.
    public func seedProgress(read: Int, inProgressPage page: Int) {
        store.lock.withLock {
            for n in 1...seriesCount {
                for c in 1...min(read, Self.chapterCount(for: n)) { store.progress["\(n)-\(c)"] = (19, true) }
                if read < Self.chapterCount(for: n) { store.progress["\(n)-\(read + 1)"] = (page, false) }
            }
        }
    }

    public func markUnread(chapters: [Chapter]) async throws {
        try await wait()
        store.lock.withLock { for chapter in chapters { store.progress[chapter.id] = nil } }
    }

    public func markSeriesUnread(_ seriesID: String) async throws {
        try await wait()
        let prefix = "\(try number(seriesID))-"
        store.lock.withLock { store.progress = store.progress.filter { !$0.key.hasPrefix(prefix) } }
    }

    public func authorize(_ request: URLRequest) -> URLRequest { request }

    public func contentFacets() async throws -> ContentFacets {
        try await wait()
        return ContentFacets(genres: ["Adventure", "Comedy", "Demo", "Horror", "Mystery"],
                             tags: config.kind == .kavita ? ["Cliffhanger"] : [],
                             supportsAgeRating: config.kind == .kavita)
    }

    /// Like the real clients: Suwayomi matches genres only.
    public func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        guard filter.isActive else { return [] }
        try await wait()
        let kavita = config.kind == .kavita
        return Set((1...seriesCount).filter { n in
            filter.hides(genres: Self.genres(for: n), tags: kavita ? Self.tags(for: n) : [],
                         ageRating: kavita ? Self.ageRating(for: n) : nil, supportsAgeRating: kavita)
        }.map(String.init))
    }
}
