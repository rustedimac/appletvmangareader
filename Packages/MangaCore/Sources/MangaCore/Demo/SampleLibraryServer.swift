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
/// series whose id is a multiple of 3.
public final class SampleLibraryServer: MangaServer, @unchecked Sendable {
    public static let words = ["Ember", "Harbor", "Lantern", "Meadow", "Orbit", "Summit", "Willow", "Zephyr"]

    public let config: ServerConfig
    public let seriesCount: Int
    /// Added before every response, to exercise loading states.
    public let latency: Duration

    private let lock = NSLock()
    /// chapterID → (zero-based page, completed)
    private var progress: [String: (page: Int, completed: Bool)] = [:]
    private var lastReadSeries: [String] = []

    public init(config: ServerConfig, seriesCount: Int = 90, latency: Duration = .milliseconds(150)) {
        self.config = config
        self.seriesCount = seriesCount
        self.latency = latency
    }

    public static func title(for n: Int) -> String {
        "\(words[(n - 1) % words.count]) Chronicles \(n)"
    }

    public static func chapterCount(for n: Int) -> Int { 3 + n % 12 }

    private func summary(_ n: Int) -> SeriesSummary {
        let read = chapters(n).filter(\.isRead).count
        return SeriesSummary(ref: SeriesRef(serverID: config.id, seriesID: String(n)),
                             title: Self.title(for: n), coverURL: nil,
                             unreadCount: Self.chapterCount(for: n) - read, libraryID: "all")
    }

    private func chapters(_ n: Int) -> [Chapter] {
        let ref = SeriesRef(serverID: config.id, seriesID: String(n))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (1...Self.chapterCount(for: n)).map { c in
            let id = "\(n)-\(c)"
            let p = lock.withLock { progress[id] }
            return Chapter(id: id, seriesRef: ref, title: "Chapter \(c)", number: Double(c), pageCount: 20,
                           lastPageRead: p?.page ?? 0, isRead: p?.completed ?? false,
                           updatedAt: base.addingTimeInterval(Double(n * 1000 + c)))
        }
    }

    private func wait() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
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
        return [MangaCategory(id: "all", name: "All Series", order: 0),
                MangaCategory(id: "short", name: "Every Third", order: 1)]
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        try await wait()
        let ids = Array(1...seriesCount).filter { category.id != "short" || $0 % 3 == 0 }
        let start = max(0, (page - 1) * pageSize)
        guard start < ids.count else { return Paged(items: [], hasMore: false) }
        let end = min(ids.count, start + pageSize)
        return Paged(items: ids[start..<end].map(summary), hasMore: end < ids.count)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        try await wait()
        switch feed {
        case .continueReading:
            return lock.withLock { lastReadSeries }.prefix(limit).compactMap { Int($0) }.map(summary)
        case .recentlyUpdated:
            return Array(stride(from: seriesCount, through: 1, by: -1).prefix(limit)).map(summary)
        case .newlyAdded:
            return Array(stride(from: seriesCount - 5, through: 1, by: -2).prefix(limit)).map(summary)
        }
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        try await wait()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return (1...seriesCount).filter { Self.title(for: $0).lowercased().contains(q) }.map(summary)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        try await wait()
        let n = try number(seriesID)
        return SeriesDetail(summary: summary(n),
                            synopsis: "A generated demo series used to try out the app without a server. Number \(n) of \(seriesCount).",
                            authors: ["Demo Author"], genres: ["Adventure", "Demo"],
                            status: n % 2 == 0 ? "Ongoing" : "Completed", chapters: chapters(n))
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        try await wait()
        return (0..<chapter.pageCount).map { i in
            PageDescriptor(index: i, url: config.baseURL.appendingPathComponent("page/\(chapter.id)/\(i).png"),
                           size: PageSize(width: 1000, height: 1500))
        }
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        lock.withLock {
            progress[chapter.id] = (page, completed)
            lastReadSeries.removeAll { $0 == chapter.seriesRef.seriesID }
            lastReadSeries.insert(chapter.seriesRef.seriesID, at: 0)
        }
    }

    /// Marks the first `read` chapters of every series read and leaves the
    /// next one open at `page`, so UI tests start with progress to undo.
    public func seedProgress(read: Int, inProgressPage page: Int) {
        lock.withLock {
            for n in 1...seriesCount {
                for c in 1...min(read, Self.chapterCount(for: n)) { progress["\(n)-\(c)"] = (19, true) }
                if read < Self.chapterCount(for: n) { progress["\(n)-\(read + 1)"] = (page, false) }
            }
        }
    }

    public func markUnread(chapters: [Chapter]) async throws {
        try await wait()
        lock.withLock { for chapter in chapters { progress[chapter.id] = nil } }
    }

    public func markSeriesUnread(_ seriesID: String) async throws {
        try await wait()
        let prefix = "\(try number(seriesID))-"
        lock.withLock { progress = progress.filter { !$0.key.hasPrefix(prefix) } }
    }

    public func authorize(_ request: URLRequest) -> URLRequest { request }
}
