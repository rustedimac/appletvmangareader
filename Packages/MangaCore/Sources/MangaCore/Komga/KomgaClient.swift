import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Komga's REST API (`api/v1`, `api/v2`), verified against Komga
/// 1.30.2. Needs Komga 1.19 or later for the `series/list` and `books/list`
/// search endpoints.
///
/// Login is an API key (`X-API-Key`, made in Komga → Account → API Keys) or
/// the user's email and password as HTTP basic auth. Both are sent on every
/// request, images included, so `authorize(_:)` adds them.
///
/// Mapping: Komga libraries are categories, series are series, and each
/// book (a volume or chapter file) is a `Chapter`. Reading progress belongs
/// to the Komga user, like Kavita.
public final class KomgaClient: MangaServer, @unchecked Sendable {
    public let config: ServerConfig
    let transport: HTTPTransport
    /// Library ids to show; nil shows every library.
    public let categoryScope: Set<String>?
    let authHeaders: [String: String]

    public init(config: ServerConfig, apiKey: String?, username: String?, password: String?,
                categoryScope: Set<String>? = nil, transport: HTTPTransport) {
        self.config = config
        self.transport = transport
        self.categoryScope = categoryScope
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !key.isEmpty {
            authHeaders = ["X-API-Key": key]
        } else if !user.isEmpty {
            let raw = "\(user):\(password ?? "")"
            authHeaders = ["Authorization": "Basic " + Data(raw.utf8).base64EncodedString()]
        } else {
            authHeaders = [:]
        }
    }

    var http: HTTPClient { HTTPClient(baseURL: config.baseURL, transport: transport, defaultHeaders: authHeaders) }

    /// The selected library ids, sorted, or nil for all.
    var scopedLibraryIDs: [String]? { categoryScope.map { $0.sorted() } }

    /// `{"libraryId": …}` conditions for the selected libraries.
    var libraryCondition: KomgaCondition? {
        guard let ids = scopedLibraryIDs else { return nil }
        return KomgaCondition.any(ids.map { .is(field: "libraryId", value: $0) })
    }

    // MARK: MangaServer

    public func validate() async throws -> String {
        guard !authHeaders.isEmpty else { throw MangaError.missingCredential }
        let user: KomgaUserDTO = try await http.get("api/v2/users/me")
        let info: KomgaActuatorInfoDTO? = try? await http.get("actuator/info")
        let version = info?.build?.version.map { " \($0)" } ?? ""
        return "Signed in to Komga\(version) as \(user.email ?? "user")"
    }

    public func categories() async throws -> [MangaCategory] {
        let libraries: [KomgaLibraryDTO] = try await http.get("api/v1/libraries")
        return libraries
            .filter { $0.unavailable != true }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .enumerated()
            .map { index, library in MangaCategory(id: library.id, name: library.name, order: index) }
            .filter { categoryScope?.contains($0.id) ?? true }
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: .default, filter: .empty)
    }

    /// Komga filters series on the server (`seriesStatus`, `readStatus`
    /// and `genre` search conditions). It keeps title order.
    public var libraryFilterSupport: LibraryFilterSupport { .all }

    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort,
                       filter: LibraryFilter) async throws -> Paged<SeriesSummary> {
        let search = KomgaSearch(condition: Self.condition(library: category.id, filter: filter.limited(to: libraryFilterSupport)))
        let result: KomgaPage<KomgaSeriesDTO> = try await http.post(
            "api/v1/series/list",
            query: ["page": String(max(0, page - 1)), "size": String(pageSize), "sort": "metadata.titleSort,asc"],
            body: search)
        let hasMore = result.last.map { !$0 } ?? (result.content.count >= pageSize)
        return Paged(items: result.content.map(summary), hasMore: hasMore)
    }

    /// The library condition, and with each filter part an `anyOf` of its
    /// choices, all combined with `allOf`.
    static func condition(library: String, filter: LibraryFilter) -> KomgaCondition? {
        var parts: [KomgaCondition?] = [.is(field: "libraryId", value: library)]
        parts.append(.any(filter.statuses.map(\.komgaValue).sorted().map { .is(field: "seriesStatus", value: $0) }))
        let read: [String]
        switch filter.readProgress {
        case .any: read = []
        case .unread: read = ["UNREAD"]
        case .inProgress: read = ["IN_PROGRESS"]
        case .unfinished: read = ["UNREAD", "IN_PROGRESS"]
        case .read: read = ["READ"]
        }
        parts.append(.any(read.map { .is(field: "readStatus", value: $0) }))
        parts.append(.any(filter.genres.sorted().map { .is(field: "genre", value: $0) }))
        return .all(parts)
    }

    public func filterGenres(in category: MangaCategory) async throws -> [String] {
        let genres: [String] = try await http.get("api/v1/genres", query: ["library_id": category.id])
        return LibraryFilter.genreList(genres)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        if scopedLibraryIDs?.isEmpty == true { return [] }
        switch feed {
        case .continueReading:
            // Books in progress, most recently read first, one row per series.
            let search = KomgaSearch(condition: .all([.is(field: "readStatus", value: "IN_PROGRESS"), libraryCondition]))
            let result: KomgaPage<KomgaBookDTO> = try await http.post(
                "api/v1/books/list",
                query: ["page": "0", "size": String(limit * 2), "sort": "readProgress.readDate,desc"],
                body: search)
            return Array(result.content.map { book -> SeriesSummary in
                var s = summary(forBook: book)
                s.feedDate = book.readProgress?.readDate ?? book.readProgress?.lastModified
                return s
            }.scoped(to: categoryScope).prefix(limit))
        case .newlyAdded, .recentlyUpdated:
            let path = feed == .newlyAdded ? "api/v1/series/new" : "api/v1/series/updated"
            // Spring reads a comma-separated value as a list.
            let result: KomgaPage<KomgaSeriesDTO> = try await http.get(
                path, query: ["page": "0", "size": String(limit), "library_id": scopedLibraryIDs?.joined(separator: ",")])
            return Array(result.content.map { dto -> SeriesSummary in
                var s = summary(dto)
                s.feedDate = feed == .newlyAdded ? dto.created : dto.lastModified
                return s
            }.scoped(to: categoryScope).prefix(limit))
        }
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, scopedLibraryIDs?.isEmpty != true else { return [] }
        let search = KomgaSearch(condition: libraryCondition, fullTextSearch: trimmed)
        let result: KomgaPage<KomgaSeriesDTO> = try await http.post(
            "api/v1/series/list", query: ["page": "0", "size": "50"], body: search)
        return result.content.map(summary).scoped(to: categoryScope)
    }

    /// The series alone has `booksCount`; no need for its book list.
    public func chapterCount(seriesID: String) async throws -> SeriesCount {
        let dto: KomgaSeriesDTO = try await http.get("api/v1/series/\(Self.pathSegment(seriesID))")
        return SeriesCount(count: dto.booksCount ?? 0, unit: .book)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        let client = http
        async let seriesTask: KomgaSeriesDTO = client.get("api/v1/series/\(Self.pathSegment(seriesID))")
        async let booksTask: KomgaPage<KomgaBookDTO> = client.post(
            "api/v1/books/list",
            query: ["unpaged": "true", "sort": "metadata.numberSort,asc"],
            body: KomgaSearch(condition: .is(field: "seriesId", value: seriesID)))
        let series = try await seriesTask
        // The library's name, for series detail ("komga.home · Comics").
        async let libraryTask = library(series.libraryId)
        let books = try await booksTask.content
        let library = await libraryTask
        let ref = ref(series.id)
        let authors = Self.uniqueAuthors(series.booksMetadata?.authors ?? books.flatMap { $0.metadata?.authors ?? [] })
        let synopsis = [series.metadata?.summary, series.booksMetadata?.summary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        var detail = SeriesDetail(
            summary: summary(series),
            synopsis: synopsis,
            authors: authors,
            genres: (series.metadata?.genres ?? []).map(Self.displayGenre),
            status: Self.statusName(series.metadata?.status),
            chapters: Self.chapters(from: books, seriesRef: ref)
        )
        if let name = library?.name, !name.isEmpty { detail.placement = SeriesPlacement(categories: [name]) }
        return detail
    }

    /// A library by id, or nil if it can't be loaded.
    func library(_ id: String?) async -> KomgaLibraryDTO? {
        guard let id else { return nil }
        return try? await http.get("api/v1/libraries/\(Self.pathSegment(id))")
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        let id = Self.pathSegment(chapter.id)
        let pages: [KomgaPageDTO] = try await http.get("api/v1/books/\(id)/pages")
        return try pages.sorted { $0.number < $1.number }.enumerated().map { index, page in
            let size: PageSize? = {
                guard let w = page.width, let h = page.height, w > 0, h > 0 else { return nil }
                return PageSize(width: w, height: h)
            }()
            return PageDescriptor(index: index, url: try http.url("api/v1/books/\(id)/pages/\(page.number)"), size: size)
        }
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        let body = completed
            ? KomgaReadProgressUpdate(page: nil, completed: true)
            : KomgaReadProgressUpdate(page: max(0, page) + 1, completed: nil)
        let request = try http.request("PATCH", "api/v1/books/\(Self.pathSegment(chapter.id))/read-progress",
                                       body: HTTPClient.encoder.encode(body))
        try await http.send(request)
    }

    /// Komga clears a book's progress with DELETE on its read-progress.
    public func markUnread(chapters: [Chapter]) async throws {
        for chapter in chapters {
            let request = try http.request("DELETE", "api/v1/books/\(Self.pathSegment(chapter.id))/read-progress")
            try await http.send(request)
        }
    }

    public func markSeriesUnread(_ seriesID: String) async throws {
        let request = try http.request("DELETE", "api/v1/series/\(Self.pathSegment(seriesID))/read-progress")
        try await http.send(request)
    }

    public func authorize(_ request: URLRequest) -> URLRequest {
        // Only send the login to this server, never to another host.
        guard request.url?.host == config.baseURL.host else { return request }
        var request = request
        for (key, value) in authHeaders { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }

    // MARK: Mapping

    func ref(_ id: String) -> SeriesRef { SeriesRef(serverID: config.id, seriesID: id) }

    func summary(_ dto: KomgaSeriesDTO) -> SeriesSummary {
        let title = dto.metadata?.title.flatMap { $0.isEmpty ? nil : $0 } ?? dto.name
        return SeriesSummary(ref: ref(dto.id), title: title, coverURL: coverURL(seriesID: dto.id),
                             unreadCount: dto.booksUnreadCount, libraryID: dto.libraryId,
                             chapterCount: dto.booksCount, countUnit: .book)
    }

    func summary(forBook book: KomgaBookDTO) -> SeriesSummary {
        SeriesSummary(ref: ref(book.seriesId), title: book.seriesTitle ?? book.name,
                      coverURL: coverURL(seriesID: book.seriesId), libraryID: book.libraryId)
    }

    func coverURL(seriesID: String) -> URL? {
        try? http.url("api/v1/series/\(Self.pathSegment(seriesID))/thumbnail")
    }

    /// Books in reading order (Komga's `numberSort`), as chapters. Komga
    /// progress pages are one-based; `Chapter.lastPageRead` is zero-based.
    static func chapters(from books: [KomgaBookDTO], seriesRef: SeriesRef) -> [Chapter] {
        let sorted = books.enumerated().sorted { a, b in
            let x = a.element.metadata?.numberSort ?? a.element.number ?? Double(a.offset)
            let y = b.element.metadata?.numberSort ?? b.element.number ?? Double(b.offset)
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
        return sorted.filter { $0.deleted != true }.enumerated().map { index, book in
            let pages = book.media?.pagesCount ?? 0
            let progress = book.readProgress
            let completed = progress?.completed == true
            let lastPage = completed ? max(pages - 1, 0) : max(0, (progress?.page ?? 1) - 1)
            return Chapter(
                id: book.id,
                seriesRef: seriesRef,
                title: chapterTitle(book),
                number: Double(index + 1),
                pageCount: pages,
                lastPageRead: min(lastPage, max(pages - 1, 0)),
                isRead: completed,
                updatedAt: book.lastModified
            )
        }
    }

    /// The book's title, or "Book N" when Komga only has the file name.
    static func chapterTitle(_ book: KomgaBookDTO) -> String {
        let title = book.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        if let number = book.metadata?.number, !number.isEmpty { return "Book \(number)" }
        return book.name
    }

    static func uniqueAuthors(_ authors: [KomgaAuthorDTO]) -> [String] {
        // Writers first, then everyone else, each name once.
        let ordered = authors.filter { $0.role?.lowercased() == "writer" } + authors.filter { $0.role?.lowercased() != "writer" }
        var seen = Set<String>()
        return ordered.map(\.name).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Komga lower-cases genres; show "sci-fi" as "Sci-Fi".
    static func displayGenre(_ genre: String) -> String {
        genre == genre.lowercased() ? genre.capitalized : genre
    }

    static func statusName(_ status: String?) -> String? {
        switch status?.uppercased() {
        case "ONGOING": return "Ongoing"
        case "ENDED": return "Completed"
        case "HIATUS": return "Hiatus"
        case "ABANDONED": return "Cancelled"
        default: return nil
        }
    }

    /// Komga ids are alphanumeric, but escape anything else so an id can't
    /// change the path.
    static func pathSegment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
    }
}
