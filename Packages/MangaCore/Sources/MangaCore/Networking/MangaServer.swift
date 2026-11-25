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

    /// A home-screen row.
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary]

    func search(_ query: String) async throws -> [SeriesSummary]

    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail

    /// Page URLs (and sizes, when the server knows them) for a chapter.
    func pages(for chapter: Chapter) async throws -> [PageDescriptor]

    /// Saves reading progress. `page` is zero-based.
    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws

    /// Marks chapters of one series as unread and clears their page
    /// progress. Does nothing for an empty list.
    func markUnread(chapters: [Chapter]) async throws

    /// Marks every chapter of a series as unread.
    func markSeriesUnread(_ seriesID: String) async throws

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

    func imageRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        return authorize(request)
    }
}

/// Creates the right client for a saved server.
public enum MangaServerFactory {
    /// `categoryScope` limits the client to these library/category ids
    /// (`ProfileServerSettings.selectedCategoryIDs`); nil means everything.
    /// An active `contentFilter` wraps the client in `ContentFilteredServer`.
    public static func make(config: ServerConfig, credential: ServerCredential?, categoryScope: Set<String>? = nil,
                            contentFilter: ContentFilter = .none,
                            transport: HTTPTransport = URLSessionTransport()) -> MangaServer {
        let client = makeUnfiltered(config: config, credential: credential, categoryScope: categoryScope,
                                    transport: transport)
        return ContentFilteredServer.wrapping(client, filter: contentFilter)
    }

    static func makeUnfiltered(config: ServerConfig, credential: ServerCredential?, categoryScope: Set<String>?,
                               transport: HTTPTransport) -> MangaServer {
        switch config.kind {
        case .kavita:
            return KavitaClient(config: config, apiKey: credential?.apiKey ?? "", categoryScope: categoryScope,
                                transport: transport)
        case .suwayomi:
            return SuwayomiClient(config: config, username: credential?.username, password: credential?.password,
                                  categoryScope: categoryScope, transport: transport)
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
