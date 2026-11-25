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

    /// Kavita libraries or Suwayomi categories.
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

    /// Adds any auth headers the server needs to fetch an image URL it
    /// returned (covers and pages).
    func authorize(_ request: URLRequest) -> URLRequest
}

public extension MangaServer {
    func imageRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        return authorize(request)
    }
}

/// Creates the right client for a saved server.
public enum MangaServerFactory {
    public static func make(config: ServerConfig, credential: ServerCredential?, transport: HTTPTransport = URLSessionTransport()) -> MangaServer {
        switch config.kind {
        case .kavita:
            return KavitaClient(config: config, apiKey: credential?.apiKey ?? "", transport: transport)
        case .suwayomi:
            return SuwayomiClient(config: config, username: credential?.username, password: credential?.password,
                                  loginMode: credential?.suwayomiLogin, transport: transport)
        }
    }
}
