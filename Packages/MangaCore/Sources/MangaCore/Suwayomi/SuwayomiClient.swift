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
    /// Category ids to show ("0" is Default); nil shows the whole library.
    public let categoryScope: Set<String>?
    /// The last library grid category, shared by its pages.
    let gridCache = SuwayomiGridCache()

    /// Suwayomi's built-in category for manga not put in any other.
    static let defaultCategoryID = "0"

    public init(config: ServerConfig, username: String?, password: String?, categoryScope: Set<String>? = nil,
                transport: HTTPTransport) {
        self.config = config
        self.transport = transport
        self.categoryScope = categoryScope
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

    public func categories() async throws -> [MangaCategory] {
        struct Response: Decodable {
            struct Category: Decodable { var id: Int; var name: String; var order: Int? }
            var categories: Nodes<Category>
        }
        let r: Response = try await graphQL("query { categories { nodes { id name order } } }")
        return r.categories.nodes
            .sorted { ($0.order ?? 0, $0.id) < ($1.order ?? 0, $1.id) }
            .map { MangaCategory(id: String($0.id), name: $0.name, order: $0.order ?? 0) }
            .filter { categoryScope?.contains($0.id) ?? true }
    }

    /// How to limit manga queries to the selected categories: `.all` when
    /// there's no limit, `.nothing` when nothing is selected, otherwise a
    /// `MangaFilter` literal.
    /// Default (id 0) has no rows in Suwayomi's category table, so it's
    /// matched as "no category".
    enum ScopeFilter: Equatable { case all, nothing, filter(String) }

    var scopeFilter: ScopeFilter {
        guard let scope = categoryScope else { return .all }
        let ids = scope.filter { $0 != Self.defaultCategoryID }.compactMap(Int.init).sorted()
        let includesDefault = scope.contains(Self.defaultCategoryID)
        var parts: [String] = []
        if !ids.isEmpty { parts.append("{categoryId: {in: [\(ids.map(String.init).joined(separator: ", "))]}}") }
        if includesDefault { parts.append("{categoryId: {isNull: true}}") }
        switch parts.count {
        case 0: return .nothing
        case 1: return .filter(parts[0])
        default: return .filter("{or: [\(parts.joined(separator: ", "))]}")
        }
    }

    /// Ids of library manga in the selected categories, for queries that
    /// can't filter by category themselves (chapters).
    func scopedMangaIDs() async throws -> [Int]? {
        switch scopeFilter {
        case .all: return nil
        case .nothing: return []
        case .filter(let filter):
            struct Response: Decodable {
                struct Manga: Decodable { var id: Int }
                var mangas: Nodes<Manga>
            }
            let r: Response = try await graphQL("query { mangas(condition: {inLibrary: true}, filter: \(filter)) { nodes { id } } }")
            var seen = Set<Int>()
            return r.mangas.nodes.map(\.id).filter { seen.insert($0).inserted }
        }
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: .default)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        switch feed {
        case .newlyAdded:
            let filter: String
            switch scopeFilter {
            case .nothing: return []
            case .all: filter = ""
            case .filter(let f): filter = ", filter: \(f)"
            }
            struct Response: Decodable { var mangas: Nodes<SuwayomiMangaDTO> }
            let r: Response = try await graphQL(
                "query($first: Int!) { mangas(condition: {inLibrary: true}\(filter), orderBy: IN_LIBRARY_AT, orderByType: DESC, first: $first) { nodes { \(SuwayomiMangaDTO.fields) inLibraryAt } } }",
                variables: ["first": .int(limit)]
            )
            return Array(r.mangas.nodes.map { m -> SeriesSummary in
                var series = summary(m)
                series.feedDate = Self.date(m.inLibraryAt)
                return series
            }.scoped(to: categoryScope).prefix(limit))
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
                var fetchedAt: FlexibleNumber?
                var manga: SuwayomiMangaDTO
            }
            var chapters: Nodes<ChapterNode>
        }
        let mangaIDs = try await scopedMangaIDs()
        if mangaIDs?.isEmpty == true { return [] }
        var variables: [String: JSONValue] = ["first": .int(limit * 10)]
        var declarations = "$first: Int!"
        var filter = "inLibrary: {equalTo: true}"
        if let mangaIDs {
            variables["ids"] = .array(mangaIDs.map { .int($0) })
            declarations += ", $ids: [Int!]"
            filter += ", mangaId: {in: $ids}"
        }
        let r: Response = try await graphQL(
            "query(\(declarations)) { chapters(filter: {\(filter)}, orderBy: \(orderBy), orderByType: DESC, first: $first) { nodes { lastReadAt fetchedAt manga { \(SuwayomiMangaDTO.fields) } } } }",
            variables: variables
        )
        var seen = Set<Int>()
        var result: [SeriesSummary] = []
        for node in r.chapters.nodes {
            if requireRead && (node.lastReadAt?.value ?? 0) <= 0 { continue }
            var series = summary(node.manga)
            series.feedDate = Self.date(requireRead ? node.lastReadAt : node.fetchedAt)
            guard ProfileServerSettings(selectedCategoryIDs: categoryScope).includes(series),
                  seen.insert(node.manga.id).inserted else { continue }
            result.append(series)
            if result.count >= limit { break }
        }
        return result
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let title = "{title: {includesInsensitive: $q}}"
        let filter: String
        switch scopeFilter {
        case .nothing: return []
        case .all: filter = title
        case .filter(let f): filter = "{and: [\(title), \(f)]}"
        }
        struct Response: Decodable { var mangas: Nodes<SuwayomiMangaDTO> }
        let r: Response = try await graphQL(
            "query($q: String!) { mangas(condition: {inLibrary: true}, filter: \(filter), first: 60) { nodes { \(SuwayomiMangaDTO.fields) } } }",
            variables: ["q": .string(trimmed)]
        )
        return r.mangas.nodes.map(summary).scoped(to: categoryScope)
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
                var categories: Nodes<SuwayomiMangaDTO.CategoryRef>?
                var source: Source?
                var chapters: Nodes<SuwayomiChapterDTO>
            }
            struct Source: Decodable { var displayName: String?; var name: String? }
            var manga: Manga
        }
        guard let id = Int(seriesID) else { throw MangaError.notFound }
        let r: Response = try await graphQL(
            "query($id: Int!) { manga(id: $id) { id title description author artist genre status thumbnailUrl unreadCount categories { nodes { id name } } source { displayName name } chapters { nodes { \(SuwayomiChapterDTO.fields) } } } }",
            variables: ["id": .int(id)]
        )
        let m = r.manga
        let ref = SeriesRef(serverID: config.id, seriesID: String(m.id))
        let authors = [m.author, m.artist].compactMap { $0 }.filter { !$0.isEmpty }
        var uniqueAuthors: [String] = []
        for a in authors where !uniqueAuthors.contains(a) { uniqueAuthors.append(a) }
        var detail = SeriesDetail(
            summary: SeriesSummary(ref: ref, title: m.title, coverURL: resolve(m.thumbnailUrl), unreadCount: m.unreadCount,
                                   categoryIDs: Self.categoryIDs(m.categories)),
            synopsis: m.description,
            authors: uniqueAuthors,
            genres: m.genre ?? [],
            status: m.status.map { $0.capitalized },
            chapters: Self.chapters(from: m.chapters.nodes, seriesRef: ref)
        )
        let placement = Self.placement(categories: m.categories, source: m.source?.displayName ?? m.source?.name)
        detail.placement = placement.isEmpty ? nil : placement
        return detail
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

    public func markUnread(chapters: [Chapter]) async throws {
        guard !chapters.isEmpty else { return }
        let ids = try chapters.map { chapter -> JSONValue in
            guard let id = Int(chapter.id) else { throw MangaError.notFound }
            return .int(id)
        }
        try await updateChaptersUnread(ids)
    }

    public func markSeriesUnread(_ seriesID: String) async throws {
        struct Response: Decodable {
            struct Manga: Decodable { var chapters: Nodes<ChapterID> }
            struct ChapterID: Decodable { var id: Int }
            var manga: Manga
        }
        guard let id = Int(seriesID) else { throw MangaError.notFound }
        let r: Response = try await graphQL("query($id: Int!) { manga(id: $id) { chapters { nodes { id } } } }",
                                            variables: ["id": .int(id)])
        let ids = r.manga.chapters.nodes.map { JSONValue.int($0.id) }
        guard !ids.isEmpty else { return }
        try await updateChaptersUnread(ids)
    }

    func updateChaptersUnread(_ ids: [JSONValue]) async throws {
        struct Response: Decodable {
            struct Payload: Decodable { var clientMutationId: String? }
            var updateChapters: Payload
        }
        let _: Response = try await graphQL(
            "mutation($ids: [Int!]!) { updateChapters(input: {ids: $ids, patch: {isRead: false, lastPageRead: 0}}) { clientMutationId } }",
            variables: ["ids": .array(ids)]
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
                      coverURL: resolve(m.thumbnailUrl), unreadCount: m.unreadCount,
                      categoryIDs: Self.categoryIDs(m.categories))
    }

    /// Category names (Default when the manga is in none) and the source.
    /// Nil `categories` means the server didn't send them.
    static func placement(categories: Nodes<SuwayomiMangaDTO.CategoryRef>?, source: String?) -> SeriesPlacement {
        let names: [String]
        if let nodes = categories?.nodes {
            names = nodes.isEmpty ? ["Default"] : nodes.compactMap(\.name)
        } else {
            names = []
        }
        // Suwayomi's local folder source isn't worth naming.
        let from = source.flatMap { $0.caseInsensitiveCompare("Local source") == .orderedSame ? nil : $0 }
        return SeriesPlacement(categories: names, source: from)
    }

    /// Suwayomi sends epoch seconds (some fields in milliseconds); 0 is "never".
    static func date(_ value: FlexibleNumber?) -> Date? {
        guard let v = value?.value, v > 0 else { return nil }
        return Date(timeIntervalSince1970: v > 100_000_000_000 ? v / 1000 : v)
    }

    /// A manga in no category is in Default.
    static func categoryIDs(_ nodes: Nodes<SuwayomiMangaDTO.CategoryRef>?) -> [String]? {
        guard let nodes else { return nil }
        let ids = nodes.nodes.map { String($0.id) }
        return ids.isEmpty ? [defaultCategoryID] : ids
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
                updatedAt: (c.uploadDate?.value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) : nil }
            )
        }
    }
}

struct SuwayomiMangaDTO: Decodable {
    static let fields = "id title thumbnailUrl unreadCount inLibrary categories { nodes { id } }"
    struct CategoryRef: Decodable { var id: Int; var name: String? }
    var id: Int
    var title: String
    var thumbnailUrl: String?
    var unreadCount: Int?
    var inLibrary: Bool?
    var categories: Nodes<CategoryRef>?
    /// Only asked for by Newly Added.
    var inLibraryAt: FlexibleNumber?
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
