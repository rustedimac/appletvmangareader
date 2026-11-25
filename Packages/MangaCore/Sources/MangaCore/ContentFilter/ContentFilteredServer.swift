import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Wraps a server client so every list it returns leaves out what a
/// profile's `ContentFilter` hides: Home feeds, a library's series, search,
/// and series detail (a hidden series reads as not found). The ids to hide
/// come from `hiddenSeriesIDs(for:)`, fetched once and cached for `ttl`
/// seconds, so a feed costs one extra request at most every few minutes.
///
/// If the hidden ids can't be loaded, the call fails instead of showing
/// unfiltered results.
public final class ContentFilteredServer: MangaServer, @unchecked Sendable {
    public let base: MangaServer
    public let filter: ContentFilter
    private let cache: HiddenSeriesCache

    /// Most extra pages fetched when a whole library page is hidden.
    static let maxSkippedPages = 10

    /// The client itself when the filter hides nothing, otherwise a wrapper.
    public static func wrapping(_ server: MangaServer, filter: ContentFilter, ttl: TimeInterval = 300) -> MangaServer {
        guard filter.isActive else { return server }
        return ContentFilteredServer(base: server, filter: filter, ttl: ttl)
    }

    public init(base: MangaServer, filter: ContentFilter, ttl: TimeInterval = 300) {
        self.base = base
        self.filter = filter
        self.cache = HiddenSeriesCache(ttl: ttl)
    }

    public var config: ServerConfig { base.config }

    /// The ids hidden on this server, cached.
    public func hiddenIDs() async throws -> Set<String> {
        guard filter.isActive else { return [] }
        let base = self.base, filter = self.filter
        return try await cache.get { try await base.hiddenSeriesIDs(for: filter) }
    }

    func visible(_ series: [SeriesSummary], hidden: Set<String>) -> [SeriesSummary] {
        series.filter { !hidden.contains($0.ref.seriesID) }
    }

    // MARK: MangaServer

    public func validate() async throws -> String { try await base.validate() }

    public func categories() async throws -> [MangaCategory] { try await base.categories() }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        let hidden = try await hiddenIDs()
        var current = page
        var result = try await base.series(in: category, page: current, pageSize: pageSize)
        var items = visible(result.items, hidden: hidden)
        // An empty page would end paging, so keep going until something
        // shows. The pager skips repeats if it asks for these pages again.
        var skipped = 0
        while items.isEmpty && result.hasMore && !result.items.isEmpty && skipped < Self.maxSkippedPages {
            skipped += 1
            current += 1
            result = try await base.series(in: category, page: current, pageSize: pageSize)
            items = visible(result.items, hidden: hidden)
        }
        return Paged(items: items, hasMore: result.hasMore && !items.isEmpty)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        let hidden = try await hiddenIDs()
        // Ask for a few more so hidden series don't leave the row short.
        let fetch = hidden.isEmpty ? limit : limit + min(hidden.count, limit)
        return Array(visible(try await base.feed(feed, limit: fetch), hidden: hidden).prefix(limit))
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let hidden = try await hiddenIDs()
        return visible(try await base.search(query), hidden: hidden)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        if try await hiddenIDs().contains(seriesID) { throw MangaError.notFound }
        return try await base.seriesDetail(seriesID)
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        try await base.pages(for: chapter)
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        try await base.saveProgress(chapter: chapter, libraryID: libraryID, page: page, completed: completed)
    }

    public func authorize(_ request: URLRequest) -> URLRequest { base.authorize(request) }

    public func contentFacets() async throws -> ContentFacets { try await base.contentFacets() }

    public func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        if filter == self.filter { return try await hiddenIDs() }
        return try await base.hiddenSeriesIDs(for: filter)
    }
}

/// One cached value with a time limit. Concurrent callers share a fetch.
actor HiddenSeriesCache {
    let ttl: TimeInterval
    private var value: Set<String>?
    private var fetchedAt: Date?
    private var inFlight: Task<Set<String>, Error>?

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func get(_ fetch: @escaping @Sendable () async throws -> Set<String>) async throws -> Set<String> {
        if let value, let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttl { return value }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await fetch() }
        inFlight = task
        do {
            let fresh = try await task.value
            value = fresh
            fetchedAt = Date()
            inFlight = nil
            return fresh
        } catch {
            inFlight = nil
            throw error
        }
    }

    func invalidate() {
        value = nil
        fetchedAt = nil
    }
}
