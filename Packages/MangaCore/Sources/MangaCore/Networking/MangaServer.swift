import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything the app needs from a backend. Kavita and Suwayomi each
/// implement this so the UI never has to care which one it is talking to.
public protocol MangaServer: Sendable {
    var config: ServerConfig { get }

    /// Checks the connection and credentials. Returns a short description
    /// of the server (e.g. version) for the "Test connection" button.
    func validate() async throws -> String

    /// The Kavita libraries or Suwayomi categories this client imports
    /// (see `MangaServerFactory.make(categoryScope:)`). Feeds and search
    /// only return series from these.
    func categories() async throws -> [MangaCategory]

    /// Series in a category, `page` starting at 1.
    func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary>

    /// Series in a category in `sort` order. Servers that can't sort keep
    /// their own order (the default implementation).
    func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary>

    /// Which library filters this server can apply. Sort & View offers
    /// only these. Default: none.
    var libraryFilterSupport: LibraryFilterSupport { get }

    /// Series in a category in `sort` order, narrowed by `filter`. Parts
    /// of `filter` outside `libraryFilterSupport` are ignored. The default
    /// ignores the filter, which is right for servers that support none.
    func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort,
                filter: LibraryFilter) async throws -> Paged<SeriesSummary>

    /// The genres used in a category, for the genre filter. Empty when the
    /// server doesn't support it.
    func filterGenres(in category: MangaCategory) async throws -> [String]

    /// A home-screen row.
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary]

    func search(_ query: String) async throws -> [SeriesSummary]

    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail

    /// How many chapters (or volumes or books) a series has, for poster
    /// captions when the listing left it out (`SeriesSummary.chapterCount`
    /// nil). The app asks lazily, for posters on screen, and caches it.
    /// The default loads series detail; clients with a lighter request
    /// override it.
    func chapterCount(seriesID: String) async throws -> SeriesCount

    /// Page URLs (and sizes, when the server knows them) for a chapter.
    func pages(for chapter: Chapter) async throws -> [PageDescriptor]

    /// Saves reading progress. `page` is zero-based.
    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws

    /// Marks chapters of one series as unread and clears their page
    /// progress. Does nothing for an empty list.
    func markUnread(chapters: [Chapter]) async throws

    /// Marks every chapter of a series as unread.
    func markSeriesUnread(_ seriesID: String) async throws

    /// Marks chapters of one series as read. Does nothing for an empty
    /// list. The default saves each chapter's progress as completed.
    func markRead(chapters: [Chapter], libraryID: String?) async throws

    /// Adds any auth headers the server needs to fetch an image URL it
    /// returned (covers and pages).
    func authorize(_ request: URLRequest) -> URLRequest

    /// The genres and tags used on the server, for the content filter
    /// settings. Not limited by `categoryScope`.
    func contentFacets() async throws -> ContentFacets

    /// Ids of the library series `filter` hides (genres, tags, age rating).
    /// Empty when the filter is inactive. Throws rather than guessing, so
    /// callers can fail closed. `ContentFilteredServer` uses this to filter
    /// every list.
    func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String>
}

public extension MangaServer {
    /// Backends without genre data offer nothing to filter on.
    func contentFacets() async throws -> ContentFacets { ContentFacets() }

    /// A backend that can't tell what a filter hides fails closed: with an
    /// active filter it shows nothing rather than everything.
    func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        guard filter.isActive else { return [] }
        throw MangaError.decoding("This server can't apply content filters.")
    }

    func markRead(chapters: [Chapter], libraryID: String?) async throws {
        for chapter in chapters {
            try await saveProgress(chapter: chapter, libraryID: libraryID,
                                   page: max(0, chapter.pageCount - 1), completed: true)
        }
    }

    func chapterCount(seriesID: String) async throws -> SeriesCount {
        let detail = try await seriesDetail(seriesID)
        return SeriesCount(chapters: detail.chapters, seriesFormat: detail.summary.format)
    }

    func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize)
    }

    var libraryFilterSupport: LibraryFilterSupport { [] }

    func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort,
                filter: LibraryFilter) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: sort)
    }

    func filterGenres(in category: MangaCategory) async throws -> [String] { [] }

    func imageRequest(_ url: URL) -> URLRequest {
        // Images follow the address API requests settled on (see
        // `ServerAddressRouter`).
        var request = URLRequest(url: ServerAddressRouter.shared.rewrite(url, for: config))
        request.timeoutInterval = 60
        return authorize(request)
    }
}

/// Creates the right client for a saved server.
public enum MangaServerFactory {
    /// `categoryScope` limits the client to these library/category ids
    /// (`ProfileServerSettings.selectedCategoryIDs`); nil means everything.
    /// An active `contentFilter` wraps the client in `ContentFilteredServer`.
    ///
    /// A server with several addresses gets a `FailoverTransport`, so the
    /// client reaches it through whichever address answers.
    public static func make(config: ServerConfig, credential: ServerCredential?, categoryScope: Set<String>? = nil,
                            contentFilter: ContentFilter = .none,
                            transport: HTTPTransport = URLSessionTransport(),
                            router: ServerAddressRouter = .shared) -> MangaServer {
        let client = makeUnfiltered(config: config, credential: credential, categoryScope: categoryScope,
                                    transport: transport, router: router)
        return ContentFilteredServer.wrapping(client, filter: contentFilter)
    }

    static func makeUnfiltered(config: ServerConfig, credential: ServerCredential?, categoryScope: Set<String>?,
                               transport: HTTPTransport, router: ServerAddressRouter) -> MangaServer {
        let transport: HTTPTransport = config.hasAlternateAddresses
            ? FailoverTransport(inner: transport, config: config, router: router)
            : transport
        switch config.kind {
        case .kavita:
            return KavitaClient(config: config, apiKey: credential?.apiKey ?? "", categoryScope: categoryScope,
                                transport: transport)
        case .suwayomi:
            return SuwayomiClient(config: config, username: credential?.username, password: credential?.password,
                                  loginMode: credential?.suwayomiLogin, categoryScope: categoryScope, transport: transport)
        case .komga:
            return KomgaClient(config: config, apiKey: credential?.apiKey, username: credential?.username,
                               password: credential?.password, categoryScope: categoryScope, transport: transport)
        case .opds:
            return OPDSClient(config: config, username: credential?.username, password: credential?.password,
                              categoryScope: categoryScope, transport: transport)
        case .freeLibrary:
            return FreeLibraryClient(config: config, categoryScope: categoryScope, transport: transport)
        }
    }
}

extension Sequence where Element == SeriesSummary {
    /// Drops series outside `scope` (nil keeps everything) and repeats.
    func scoped(to scope: Set<String>?) -> [SeriesSummary] {
        let settings = ProfileServerSettings(selectedCategoryIDs: scope)
        var seen = Set<SeriesRef>()
        return filter { settings.includes($0) && seen.insert($0.ref).inserted }
    }
}
