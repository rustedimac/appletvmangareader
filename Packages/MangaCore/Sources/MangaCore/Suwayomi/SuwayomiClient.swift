import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Suwayomi-Server's GraphQL API (`/api/graphql`). Only library
/// content is used: browsing sources and downloading are out of scope.
///
/// Auth (see docs/PROGRESS_SYNC.md): none, HTTP basic auth, or, for servers
/// in `UI_LOGIN` mode, the `login` mutation and Bearer tokens. Tokens are
/// refreshed, or the client logs in again, when the server answers 401.
public final class SuwayomiClient: MangaServer, @unchecked Sendable {
    public let config: ServerConfig
    let transport: HTTPTransport
    let username: String?
    let password: String?
    let loginMode: SuwayomiLoginMode
    let authHeader: String?
    private let tokens = SuwayomiTokens()

    public init(config: ServerConfig, username: String?, password: String?,
                loginMode: SuwayomiLoginMode? = nil, transport: HTTPTransport) {
        self.config = config
        self.transport = transport
        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = user?.isEmpty == false ? user : nil
        self.password = password
        self.loginMode = loginMode ?? .basic
        if let user = self.username, self.loginMode == .basic {
            let raw = "\(user):\(password ?? "")"
            authHeader = "Basic " + Data(raw.utf8).base64EncodedString()
        } else {
            authHeader = nil
        }
    }

    /// Headers for the current login: basic auth, or the Bearer token.
    var authHeaders: [String: String] {
        if let authHeader { return ["Authorization": authHeader] }
        if let token = tokens.accessToken { return ["Authorization": "Bearer \(token)"] }
        return [:]
    }

    var http: HTTPClient {
        HTTPClient(baseURL: config.baseURL, transport: transport, defaultHeaders: authHeaders)
    }

    // MARK: GraphQL plumbing

    func graphQL<T: Decodable>(_ query: String, variables: [String: JSONValue] = [:], as type: T.Type = T.self) async throws -> T {
        guard loginMode == .token, username != nil else {
            return try await rawGraphQL(query, variables: variables, client: http)
        }
        if tokens.accessToken == nil { try await signIn() }
        do {
            return try await rawGraphQL(query, variables: variables, client: http)
        } catch let error as MangaError where error.isAuthFailure {
            try await renewToken()
            return try await rawGraphQL(query, variables: variables, client: http)
        }
    }

    func rawGraphQL<T: Decodable>(_ query: String, variables: [String: JSONValue], client: HTTPClient) async throws -> T {
        let body = GraphQLRequest(query: query, variables: variables)
        let request = try client.request("POST", "api/graphql", body: HTTPClient.encoder.encode(body))
        let data = try await client.send(request)
        let response = try HTTPClient.decode(GraphQLResponse<T>.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            let messages = errors.map(\.message)
            if messages.contains(where: { $0.localizedCaseInsensitiveContains("unauthorized") }) {
                throw MangaError.unauthorized
            }
            throw MangaError.graphQL(messages)
        }
        guard let value = response.data else { throw MangaError.decoding("GraphQL response had no data") }
        return value
    }

    // MARK: Login (UI_LOGIN)

    struct LoginResponse: Decodable {
        struct Payload: Decodable { var accessToken: String; var refreshToken: String }
        var login: Payload
    }

    /// Logs in with the `login` mutation and keeps the tokens.
    func signIn() async throws {
        guard let username else { throw MangaError.missingCredential }
        let anonymous = HTTPClient(baseURL: config.baseURL, transport: transport)
        let r: LoginResponse = try await rawGraphQL(
            "mutation($u: String!, $p: String!) { login(input: {username: $u, password: $p}) { accessToken refreshToken } }",
            variables: ["u": .string(username), "p": .string(password ?? "")], client: anonymous)
        tokens.set(access: r.login.accessToken, refresh: r.login.refreshToken)
    }

    /// New access token from the refresh token, or a fresh login.
    func renewToken() async throws {
        struct Response: Decodable {
            struct Payload: Decodable { var accessToken: String }
            var refreshToken: Payload
        }
        if let refresh = tokens.refreshToken {
            let anonymous = HTTPClient(baseURL: config.baseURL, transport: transport)
            if let r: Response = try? await rawGraphQL(
                "mutation($t: String!) { refreshToken(input: {refreshToken: $t}) { accessToken } }",
                variables: ["t": .string(refresh)], client: anonymous) {
                tokens.set(access: r.refreshToken.accessToken, refresh: refresh)
                return
            }
        }
        tokens.clear()
        try await signIn()
    }

    /// Works out how a server takes this username and password: the
    /// `login` mutation when it answers it, else basic auth.
    public static func detectLoginMode(config: ServerConfig, username: String, password: String,
                                       transport: HTTPTransport) async -> SuwayomiLoginMode {
        let probe = SuwayomiClient(config: config, username: username, password: password,
                                   loginMode: .token, transport: transport)
        do {
            try await probe.signIn()
            return .token
        } catch {
            return .basic
        }
    }

    /// The signed-in user on servers with user accounts (Suwayomi preview
    /// builds), or nil when the server has a single shared progress. Only
    /// a `login` sign-in maps to a user; every other mode is user 1.
    public func currentUser() async -> String? {
        guard loginMode == .token, username != nil else { return nil }
        struct Response: Decodable {
            struct User: Decodable { var username: String? }
            var user: User?
        }
        guard let r: Response = try? await graphQL("query { user { username } }") else { return nil }
        return r.user?.username
    }

    // MARK: MangaServer

    public func validate() async throws -> String {
        struct Response: Decodable {
            struct About: Decodable { var name: String?; var version: String? }
            var aboutServer: About
        }
        let r: Response = try await graphQL("query { aboutServer { name version } }")
        return "Connected to \(r.aboutServer.name ?? "Suwayomi") \(r.aboutServer.version ?? "")"
            .trimmingCharacters(in: .whitespaces)
    }

    public func categories() async throws -> [MangaCategory] {
        struct Response: Decodable {
            struct Category: Decodable { var id: Int; var name: String; var order: Int? }
            var categories: Nodes<Category>
        }
        let r: Response = try await graphQL("query { categories { nodes { id name order } } }")
        return r.categories.nodes
            .sorted { ($0.order ?? 0, $0.id) < ($1.order ?? 0, $1.id) }
            .map { MangaCategory(id: String($0.id), name: $0.name, order: $0.order ?? 0) }
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        struct Response: Decodable {
            struct Category: Decodable { var mangas: Nodes<SuwayomiMangaDTO> }
            var category: Category
        }
        guard let id = Int(category.id) else { throw MangaError.notFound }
        let r: Response = try await graphQL(
            "query($id: Int!) { category(id: $id) { mangas { nodes { \(SuwayomiMangaDTO.fields) } } } }",
            variables: ["id": .int(id)]
        )
        // Suwayomi returns a whole category at once; page it client-side.
        let all = r.category.mangas.nodes
            .filter { $0.inLibrary != false }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let start = max(0, (page - 1) * pageSize)
        guard start < all.count else { return Paged(items: [], hasMore: false) }
        let end = min(all.count, start + pageSize)
        return Paged(items: all[start..<end].map(summary), hasMore: end < all.count)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        switch feed {
        case .newlyAdded:
            struct Response: Decodable { var mangas: Nodes<SuwayomiMangaDTO> }
            let r: Response = try await graphQL(
                "query($first: Int!) { mangas(condition: {inLibrary: true}, orderBy: IN_LIBRARY_AT, orderByType: DESC, first: $first) { nodes { \(SuwayomiMangaDTO.fields) } } }",
                variables: ["first": .int(limit)]
            )
            return r.mangas.nodes.map(summary)
        case .recentlyUpdated:
            return try await chapterFeed(orderBy: "FETCHED_AT", limit: limit, requireRead: false)
        case .continueReading:
            return try await chapterFeed(orderBy: "LAST_READ_AT", limit: limit, requireRead: true)
        }
    }

    /// Builds a series list from the most recent chapters by some ordering,
    /// one entry per series.
    func chapterFeed(orderBy: String, limit: Int, requireRead: Bool) async throws -> [SeriesSummary] {
        struct Response: Decodable {
            struct ChapterNode: Decodable {
                var lastReadAt: FlexibleNumber?
                var manga: SuwayomiMangaDTO
            }
            var chapters: Nodes<ChapterNode>
        }
        let r: Response = try await graphQL(
            "query($first: Int!) { chapters(filter: {inLibrary: {equalTo: true}}, orderBy: \(orderBy), orderByType: DESC, first: $first) { nodes { lastReadAt manga { \(SuwayomiMangaDTO.fields) } } } }",
            variables: ["first": .int(limit * 10)]
        )
        var seen = Set<Int>()
        var result: [SeriesSummary] = []
        for node in r.chapters.nodes {
            if requireRead && (node.lastReadAt?.value ?? 0) <= 0 { continue }
            guard seen.insert(node.manga.id).inserted else { continue }
            result.append(summary(node.manga))
            if result.count >= limit { break }
        }
        return result
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        struct Response: Decodable { var mangas: Nodes<SuwayomiMangaDTO> }
        let r: Response = try await graphQL(
            "query($q: String!) { mangas(condition: {inLibrary: true}, filter: {title: {includesInsensitive: $q}}, first: 60) { nodes { \(SuwayomiMangaDTO.fields) } } }",
            variables: ["q": .string(trimmed)]
        )
        return r.mangas.nodes.map(summary)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        struct Response: Decodable {
            struct Manga: Decodable {
                var id: Int
                var title: String
                var description: String?
                var author: String?
                var artist: String?
                var genre: [String]?
                var status: String?
                var thumbnailUrl: String?
                var unreadCount: Int?
                var chapters: Nodes<SuwayomiChapterDTO>
            }
            var manga: Manga
        }
        guard let id = Int(seriesID) else { throw MangaError.notFound }
        let r: Response = try await graphQL(
            "query($id: Int!) { manga(id: $id) { id title description author artist genre status thumbnailUrl unreadCount chapters { nodes { \(SuwayomiChapterDTO.fields) } } } }",
            variables: ["id": .int(id)]
        )
        let m = r.manga
        let ref = SeriesRef(serverID: config.id, seriesID: String(m.id))
        let authors = [m.author, m.artist].compactMap { $0 }.filter { !$0.isEmpty }
        var uniqueAuthors: [String] = []
        for a in authors where !uniqueAuthors.contains(a) { uniqueAuthors.append(a) }
        return SeriesDetail(
            summary: SeriesSummary(ref: ref, title: m.title, coverURL: resolve(m.thumbnailUrl), unreadCount: m.unreadCount),
            synopsis: m.description,
            authors: uniqueAuthors,
            genres: m.genre ?? [],
            status: m.status.map { $0.capitalized },
            chapters: Self.chapters(from: m.chapters.nodes, seriesRef: ref)
        )
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        struct Response: Decodable {
            struct Payload: Decodable { var pages: [String] }
            var fetchChapterPages: Payload
        }
        guard let id = Int(chapter.id) else { throw MangaError.notFound }
        let r: Response = try await graphQL(
            "mutation($id: Int!) { fetchChapterPages(input: {chapterId: $id}) { pages } }",
            variables: ["id": .int(id)]
        )
        return r.fetchChapterPages.pages.enumerated().compactMap { index, path in
            resolve(path).map { PageDescriptor(index: index, url: $0) }
        }
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        struct Response: Decodable {
            struct Payload: Decodable { var clientMutationId: String? }
            var updateChapter: Payload
        }
        guard let id = Int(chapter.id) else { throw MangaError.notFound }
        let _: Response = try await graphQL(
            "mutation($id: Int!, $page: Int!, $read: Boolean!) { updateChapter(input: {id: $id, patch: {lastPageRead: $page, isRead: $read}}) { clientMutationId } }",
            variables: ["id": .int(id), "page": .int(max(0, page)), "read": .bool(completed)]
        )
    }

    public func authorize(_ request: URLRequest) -> URLRequest {
        var r = request
        for (key, value) in authHeaders { r.setValue(value, forHTTPHeaderField: key) }
        return r
    }

    // MARK: Helpers

    /// Suwayomi returns server-relative paths like `/api/v1/manga/1/thumbnail`.
    /// Join them to the base URL, keeping any reverse-proxy path prefix.
    func resolve(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        var base = config.baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + (path.hasPrefix("/") ? path : "/" + path))
    }

    func summary(_ m: SuwayomiMangaDTO) -> SeriesSummary {
        SeriesSummary(ref: SeriesRef(serverID: config.id, seriesID: String(m.id)), title: m.title,
                      coverURL: resolve(m.thumbnailUrl), unreadCount: m.unreadCount)
    }

    /// Orders chapters oldest to newest. Suwayomi's `sourceOrder` follows
    /// the source's list; we check the chapter numbers to pick the direction.
    static func chapters(from nodes: [SuwayomiChapterDTO], seriesRef: SeriesRef) -> [Chapter] {
        var sorted = nodes.sorted { ($0.sourceOrder ?? 0) < ($1.sourceOrder ?? 0) }
        let numbered = sorted.compactMap { $0.chapterNumber }.filter { $0 >= 0 }
        if let first = numbered.first, let last = numbered.last, first > last {
            sorted.reverse()
        }
        return sorted.enumerated().map { index, c in
            let pageCount = max(0, c.pageCount ?? 0)
            return Chapter(
                id: String(c.id),
                seriesRef: seriesRef,
                volumeID: nil,
                title: c.name ?? "Chapter \(c.chapterNumber.map { String(format: "%g", $0) } ?? String(index + 1))",
                number: Double(index + 1),
                pageCount: pageCount,
                lastPageRead: max(0, c.lastPageRead ?? 0),
                isRead: c.isRead ?? false,
                updatedAt: (c.uploadDate?.value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) : nil },
                lastReadAt: (c.lastReadAt?.value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) : nil }
            )
        }
    }
}

struct SuwayomiMangaDTO: Decodable {
    static let fields = "id title thumbnailUrl unreadCount inLibrary"
    var id: Int
    var title: String
    var thumbnailUrl: String?
    var unreadCount: Int?
    var inLibrary: Bool?
}

struct SuwayomiChapterDTO: Decodable {
    static let fields = "id name chapterNumber sourceOrder isRead lastPageRead lastReadAt pageCount uploadDate"
    var id: Int
    var name: String?
    var chapterNumber: Double?
    var sourceOrder: Int?
    var isRead: Bool?
    var lastPageRead: Int?
    var lastReadAt: FlexibleNumber?
    var pageCount: Int?
    var uploadDate: FlexibleNumber?
}

/// Access and refresh tokens for `UI_LOGIN` servers. Read synchronously by
/// `authorize(_:)` for image requests, so it's a lock, not an actor.
final class SuwayomiTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var access: String?
    private var refresh: String?

    var accessToken: String? { lock.withLock { access } }
    var refreshToken: String? { lock.withLock { refresh } }

    func set(access: String, refresh: String) {
        lock.withLock { self.access = access; self.refresh = refresh }
    }

    func clear() { lock.withLock { access = nil; refresh = nil } }
}

struct Nodes<T: Decodable>: Decodable {
    var nodes: [T]
}

struct GraphQLRequest: Encodable {
    var query: String
    var variables: [String: JSONValue]
}

struct GraphQLResponse<T: Decodable>: Decodable {
    struct GraphQLError: Decodable { var message: String }
    var data: T?
    var errors: [GraphQLError]?
}

public enum JSONValue: Encodable, Hashable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    case null

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

/// Suwayomi encodes 64-bit timestamps as `LongString` (a JSON string), but
/// accept plain numbers too.
struct FlexibleNumber: Decodable, Hashable {
    var value: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self), let d = Double(s) {
            value = d
        } else {
            value = 0
        }
    }
}
