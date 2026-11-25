import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Suwayomi-Server's GraphQL API (`/api/graphql`). Only library
/// content is used: browsing sources and downloading are out of scope.
public final class SuwayomiClient: MangaServer, @unchecked Sendable {
    public let config: ServerConfig
    let transport: HTTPTransport
    let authHeader: String?

    public init(config: ServerConfig, username: String?, password: String?, transport: HTTPTransport) {
        self.config = config
        self.transport = transport
        if let username, !username.isEmpty {
            let raw = "\(username):\(password ?? "")"
            authHeader = "Basic " + Data(raw.utf8).base64EncodedString()
        } else {
            authHeader = nil
        }
    }

    var http: HTTPClient {
        HTTPClient(baseURL: config.baseURL, transport: transport,
                   defaultHeaders: authHeader.map { ["Authorization": $0] } ?? [:])
    }

    // MARK: GraphQL plumbing

    func graphQL<T: Decodable>(_ query: String, variables: [String: JSONValue] = [:], as type: T.Type = T.self) async throws -> T {
        let body = GraphQLRequest(query: query, variables: variables)
        let request = try http.request("POST", "api/graphql", body: HTTPClient.encoder.encode(body))
        let data = try await http.send(request)
        let response = try HTTPClient.decode(GraphQLResponse<T>.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw MangaError.graphQL(errors.map(\.message))
        }
        guard let value = response.data else { throw MangaError.decoding("GraphQL response had no data") }
        return value
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

    /// Suwayomi's built-in "Default" category. It holds library manga that
    /// are in no other category, and is hidden when empty.
    static let defaultCategoryID = 0

    public func categories() async throws -> [MangaCategory] {
        struct Response: Decodable {
            struct Count: Decodable { var totalCount: Int? }
            struct Category: Decodable { var id: Int; var name: String; var order: Int?; var mangas: Count? }
            var categories: Nodes<Category>
        }
        let r: Response = try await graphQL("query { categories { nodes { id name order mangas { totalCount } } } }")
        return r.categories.nodes
            .filter { $0.id != Self.defaultCategoryID || ($0.mangas?.totalCount ?? 1) > 0 }
            .sorted { ($0.order ?? 0, $0.id) < ($1.order ?? 0, $1.id) }
            .map { MangaCategory(id: String($0.id), name: $0.name, order: $0.order ?? 0) }
    }

    /// Pages on the server. `category.mangas` takes no arguments, so this
    /// uses the top-level `mangas` query filtered by category id. The Default
    /// category (id 0) isn't a real category row, so it is listed whole and
    /// paged here.
    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        guard let id = Int(category.id) else { throw MangaError.notFound }
        if id == Self.defaultCategoryID { return try await defaultCategorySeries(page: page, pageSize: pageSize) }
        struct Response: Decodable {
            struct PageInfo: Decodable { var hasNextPage: Bool }
            struct Mangas: Decodable { var totalCount: Int?; var pageInfo: PageInfo?; var nodes: [SuwayomiMangaDTO] }
            var mangas: Mangas
        }
        let offset = max(0, page - 1) * pageSize
        let r: Response = try await graphQL(
            "query($ids: [Int!], $first: Int!, $offset: Int!) { mangas(condition: {categoryIds: $ids, inLibrary: true}, orderBy: TITLE, orderByType: ASC, first: $first, offset: $offset) { totalCount pageInfo { hasNextPage } nodes { \(SuwayomiMangaDTO.fields) } } }",
            variables: ["ids": .array([.int(id)]), "first": .int(pageSize), "offset": .int(offset)]
        )
        let hasMore = r.mangas.pageInfo?.hasNextPage
            ?? r.mangas.totalCount.map { offset + r.mangas.nodes.count < $0 }
            ?? (r.mangas.nodes.count >= pageSize)
        return Paged(items: r.mangas.nodes.map(summary), hasMore: hasMore)
    }

    func defaultCategorySeries(page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        struct Response: Decodable {
            struct Category: Decodable { var mangas: Nodes<SuwayomiMangaDTO> }
            var category: Category
        }
        let r: Response = try await graphQL(
            "query($id: Int!) { category(id: $id) { mangas { nodes { \(SuwayomiMangaDTO.fields) } } } }",
            variables: ["id": .int(Self.defaultCategoryID)]
        )
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
            }
            var manga: Manga
            var chapters: Nodes<SuwayomiChapterDTO>
        }
        guard let id = Int(seriesID) else { throw MangaError.notFound }
        // `manga.chapters` takes no arguments, so ask for the chapters with
        // the top-level query, in source order (ascending = oldest first).
        let r: Response = try await graphQL(
            "query($id: Int!) { manga(id: $id) { id title description author artist genre status thumbnailUrl unreadCount } chapters(condition: {mangaId: $id}, orderBy: SOURCE_ORDER, orderByType: ASC) { nodes { \(SuwayomiChapterDTO.fields) } } }",
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
            chapters: Self.chapters(from: r.chapters.nodes, seriesRef: ref)
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
        if let authHeader { r.setValue(authHeader, forHTTPHeaderField: "Authorization") }
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

    /// Orders chapters oldest to newest by `sourceOrder` (Suwayomi numbers the
    /// source's list so that ascending is oldest first). If the known chapter
    /// numbers clearly run the other way, the list is reversed. A
    /// `chapterNumber` of -1 means the source gave no number.
    static func chapters(from nodes: [SuwayomiChapterDTO], seriesRef: SeriesRef) -> [Chapter] {
        var sorted = nodes.enumerated()
            .sorted { ($0.element.sourceOrder ?? $0.offset, $0.offset) < ($1.element.sourceOrder ?? $1.offset, $1.offset) }
            .map(\.element)
        let numbered = sorted.compactMap(\.knownNumber)
        if numbered.count >= 2, let first = numbered.first, let last = numbered.last, first > last {
            sorted.reverse()
        }
        return sorted.enumerated().map { index, c in
            let pageCount = max(0, c.pageCount ?? 0)
            return Chapter(
                id: String(c.id),
                seriesRef: seriesRef,
                volumeID: nil,
                title: Self.title(for: c, position: index + 1),
                number: Double(index + 1),
                pageCount: pageCount,
                lastPageRead: max(0, c.lastPageRead ?? 0),
                isRead: c.isRead ?? false,
                updatedAt: (c.uploadDate?.value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) : nil }
            )
        }
    }

    static func title(for c: SuwayomiChapterDTO, position: Int) -> String {
        if let name = c.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let number = c.knownNumber { return "Chapter \(String(format: "%g", number))" }
        return "Chapter \(position)"
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
    static let fields = "id name chapterNumber sourceOrder isRead lastPageRead pageCount uploadDate"
    var id: Int
    var name: String?
    var chapterNumber: Double?
    var sourceOrder: Int?
    var isRead: Bool?
    var lastPageRead: Int?
    var pageCount: Int?
    var uploadDate: FlexibleNumber?

    /// The chapter number, or nil when the source gave none (-1).
    var knownNumber: Double? {
        guard let n = chapterNumber, n >= 0 else { return nil }
        return n
    }
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
    case array([JSONValue])
    case null

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
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
