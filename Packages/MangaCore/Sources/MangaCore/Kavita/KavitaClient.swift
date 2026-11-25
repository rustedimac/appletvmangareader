import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Kavita's REST API, signed in as one Kavita user through one
/// of that user's auth keys (see docs/PROGRESS_SYNC.md).
///
/// API calls send the key in the `x-api-key` header, so the client never
/// logs in and never replaces the user's refresh token (Kavita keeps one
/// per user, and a new login would sign their web browser out). Servers
/// that predate `x-api-key` answer 401; the client then exchanges the key
/// for a JWT through `api/Plugin/authenticate` and uses that from then on.
/// Image URLs carry the key as a query parameter, which Kavita accepts.
public final class KavitaClient: MangaServer, @unchecked Sendable {
    public let config: ServerConfig
    let apiKey: String
    let transport: HTTPTransport
    /// Library ids to show; nil shows every library.
    public let categoryScope: Set<String>?
    private let tokenCache = TokenCache()

    public static let pluginName = "AppleTVMangaReader"
    /// Name of the auth key the app creates on a user's account at sign-in.
    public static let authKeyName = "Apple TV Manga Reader"

    /// Kavita's sentinel volume numbers.
    static let looseLeafVolumeNumber: Double = -100_000
    static let specialVolumeNumber: Double = 100_000

    public init(config: ServerConfig, apiKey: String, categoryScope: Set<String>? = nil, transport: HTTPTransport) {
        self.config = config
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryScope = categoryScope
        self.transport = transport
    }

    /// The selected library ids as numbers, sorted, or nil for all.
    var scopedLibraryIDs: [Int]? {
        categoryScope.map { $0.compactMap(Int.init).sorted() }
    }

    private var anonymous: HTTPClient { HTTPClient(baseURL: config.baseURL, transport: transport) }

    // MARK: Sign-in

    /// Signs in with a Kavita username and password and returns a
    /// credential holding one of that user's auth keys: the app's own key
    /// ("Apple TV Manga Reader", no expiry), created on first sign-in, or
    /// the account's OPDS key when the user may not create keys. The
    /// password is not kept.
    public static func signIn(baseURL: URL, username: String, password: String,
                              transport: HTTPTransport, now: Date = Date()) async throws -> ServerCredential {
        let http = HTTPClient(baseURL: baseURL, transport: transport)
        let user: KavitaUserDTO = try await http.post(
            "api/Account/login",
            body: KavitaLoginDTO(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        )
        let name = user.username ?? username
        if let existing = user.authKeys?.first(where: { $0.name == authKeyName && !$0.isExpired(now: now) }),
           !existing.key.isEmpty {
            return ServerCredential(apiKey: existing.key, username: name)
        }
        if let token = user.token, !token.isEmpty {
            let authed = HTTPClient(baseURL: baseURL, transport: transport,
                                    defaultHeaders: ["Authorization": "Bearer \(token)"])
            let created: KavitaAuthKeyDTO? = try? await authed.post(
                "api/Account/create-auth-key",
                body: KavitaCreateAuthKeyDTO(keyLength: 32, name: authKeyName, expiresUtc: nil)
            )
            if let key = created?.key, !key.isEmpty {
                return ServerCredential(apiKey: key, username: name)
            }
        }
        if let key = user.apiKey, !key.isEmpty {
            return ServerCredential(apiKey: key, username: name)
        }
        throw MangaError.unauthorized
    }

    // MARK: Auth

    /// Exchanges the key for a JWT. Also tells us whose key it is.
    func login() async throws -> KavitaUserDTO {
        guard !apiKey.isEmpty else { throw MangaError.missingCredential }
        let request = try anonymous.request("POST", "api/Plugin/authenticate",
                                            query: ["apiKey": apiKey, "pluginName": Self.pluginName])
        let data = try await anonymous.send(request)
        let user = try HTTPClient.decode(KavitaUserDTO.self, from: data)
        guard let token = user.token, !token.isEmpty else { throw MangaError.unauthorized }
        await tokenCache.set(token)
        return user
    }

    func authed() async throws -> HTTPClient {
        guard !apiKey.isEmpty else { throw MangaError.missingCredential }
        guard await tokenCache.usesJWT else {
            return HTTPClient(baseURL: config.baseURL, transport: transport, defaultHeaders: ["x-api-key": apiKey])
        }
        let token: String
        if let cached = await tokenCache.token {
            token = cached
        } else {
            _ = try await login()
            guard let fresh = await tokenCache.token else { throw MangaError.unauthorized }
            token = fresh
        }
        return HTTPClient(baseURL: config.baseURL, transport: transport,
                          defaultHeaders: ["Authorization": "Bearer \(token)"])
    }

    /// Runs a call. On 401 with the key header, falls back to a JWT once
    /// (older Kavita); with a JWT, logs in again once (expired token).
    func withAuth<T>(_ body: (HTTPClient) async throws -> T) async throws -> T {
        do {
            return try await body(try await authed())
        } catch MangaError.unauthorized {
            if await tokenCache.usesJWT {
                await tokenCache.clear()
            } else {
                _ = try await login()
                await tokenCache.useJWT()
            }
            return try await body(try await authed())
        }
    }

    // MARK: MangaServer

    public func validate() async throws -> String {
        let user = try await login()
        return "Signed in to Kavita as \(user.username ?? "user")"
    }

    /// The Kavita user this key belongs to.
    public func username() async throws -> String? {
        try await login().username
    }

    public func categories() async throws -> [MangaCategory] {
        let libraries: [KavitaLibraryDTO] = try await withAuth { try await $0.get("api/Library/libraries") }
        return libraries.enumerated()
            .map { index, lib in MangaCategory(id: String(lib.id), name: lib.name, order: index) }
            .filter { categoryScope?.contains($0.id) ?? true }
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: .default)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        let libraries = scopedLibraryIDs
        if libraries?.isEmpty == true { return [] }
        switch feed {
        case .continueReading:
            // On Deck filters by one library (0 = all). With several picked,
            // ask for more and drop the rest.
            let single = libraries?.count == 1 ? libraries![0] : 0
            let fetch = libraries == nil || single != 0 ? limit : limit * 4
            let items: [KavitaSeriesDTO] = try await withAuth {
                try await $0.post("api/Series/on-deck",
                                  query: ["pageNumber": "1", "pageSize": String(fetch), "libraryId": String(single)],
                                  body: EmptyBody())
            }
            return Array(items.map(summary).scoped(to: categoryScope).prefix(limit))
        case .newlyAdded:
            var filter = KavitaFilterV2()
            if let libraries { filter.statements = [KavitaFilterV2.libraries(libraries)] }
            let items: [KavitaSeriesDTO] = try await withAuth {
                try await $0.post("api/Series/recently-added-v2",
                                  query: ["pageNumber": "1", "pageSize": String(limit)],
                                  body: filter)
            }
            return Array(items.map(summary).scoped(to: categoryScope).prefix(limit))
        case .recentlyUpdated:
            // Kavita returns a fixed-size list with no library filter.
            let items: [KavitaRecentlyUpdatedDTO] = try await withAuth {
                try await $0.post("api/Series/recently-updated-series", body: EmptyBody())
            }
            let all = items.map {
                SeriesSummary(ref: ref($0.seriesId), title: $0.seriesName ?? "Untitled",
                              coverURL: coverURL(seriesID: $0.seriesId), libraryID: $0.libraryId.map(String.init))
            }
            return Array(all.scoped(to: categoryScope).prefix(limit))
        }
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, scopedLibraryIDs?.isEmpty != true else { return [] }
        let group: KavitaSearchResultGroupDTO = try await withAuth {
            try await $0.get("api/Search/search", query: ["queryString": trimmed, "includeChapterAndFiles": "false"])
        }
        // Kavita's search has no library filter.
        return (group.series ?? []).map {
            SeriesSummary(ref: ref($0.seriesId), title: $0.name, coverURL: coverURL(seriesID: $0.seriesId),
                          libraryID: $0.libraryId.map(String.init), format: ContentFormat(kavitaFormat: $0.format))
        }.scoped(to: categoryScope)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        guard let id = Int(seriesID) else { throw MangaError.notFound }
        return try await withAuth { client in
            async let seriesTask: KavitaSeriesDTO = client.get("api/Series/\(id)")
            async let volumesTask: [KavitaVolumeDTO] = client.get("api/Series/volumes", query: ["seriesId": seriesID])
            let metadata: KavitaSeriesMetadataDTO? = try? await client.get("api/Series/metadata", query: ["seriesId": seriesID])
            let series = try await seriesTask
            let volumes = try await volumesTask
            var detail = SeriesDetail(
                summary: summary(series),
                synopsis: metadata?.summary,
                authors: metadata?.writers?.map(\.name) ?? [],
                genres: metadata?.genres?.map(\.title) ?? [],
                status: KavitaPublicationStatus.name(metadata?.publicationStatus),
                chapters: Self.chapters(from: volumes, seriesRef: ref(id),
                                        seriesFormat: ContentFormat(kavitaFormat: series.format))
            )
            // Kavita sends 0001-01-01 for "never".
            detail.latestChapterAt = series.lastChapterAdded.flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
            return detail
        }
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        let dimensions: [KavitaFileDimensionDTO]? = try? await withAuth {
            try await $0.get("api/Reader/file-dimensions", query: ["chapterId": chapter.id, "extractPdf": "true"])
        }
        let sizes = Dictionary((dimensions ?? []).map { ($0.pageNumber, PageSize(width: $0.width, height: $0.height)) },
                               uniquingKeysWith: { first, _ in first })
        let count = max(chapter.pageCount, dimensions?.count ?? 0)
        return try (0..<count).map { index in
            PageDescriptor(index: index, url: try pageURL(chapterID: chapter.id, page: index), size: sizes[index])
        }
    }

    /// Kavita works out the volume, series and library from the chapter, so
    /// only the chapter id and page matter; the rest is sent when known.
    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        guard let chapterID = Int(chapter.id) else { throw MangaError.notFound }
        let body = KavitaProgressDTO(volumeId: chapter.volumeID.flatMap(Int.init) ?? 0, chapterId: chapterID,
                                     pageNum: completed ? max(chapter.pageCount, page + 1) : max(0, page),
                                     seriesId: Int(chapter.seriesRef.seriesID) ?? 0,
                                     libraryId: libraryID.flatMap(Int.init) ?? 0)
        try await withAuth { try await $0.postIgnoringResponse("api/Reader/progress", body: body) }
    }

    public func markUnread(chapters: [Chapter]) async throws {
        guard let first = chapters.first else { return }
        guard let seriesID = Int(first.seriesRef.seriesID) else { throw MangaError.notFound }
        let ids = try chapters.map { chapter -> Int in
            guard let id = Int(chapter.id), chapter.seriesRef == first.seriesRef else { throw MangaError.notFound }
            return id
        }
        let body = KavitaMarkMultipleDTO(seriesId: seriesID, volumeIds: [], chapterIds: ids)
        try await withAuth { try await $0.postIgnoringResponse("api/Reader/mark-multiple-unread", body: body) }
    }

    public func markSeriesUnread(_ seriesID: String) async throws {
        guard let id = Int(seriesID) else { throw MangaError.notFound }
        try await withAuth { try await $0.postIgnoringResponse("api/Reader/mark-unread", body: KavitaMarkSeriesDTO(seriesId: id)) }
    }

    public func authorize(_ request: URLRequest) -> URLRequest {
        request // API key is already in image URLs.
    }

    // MARK: Helpers

    func ref(_ id: Int) -> SeriesRef { SeriesRef(serverID: config.id, seriesID: String(id)) }

    func summary(_ dto: KavitaSeriesDTO) -> SeriesSummary {
        let unread: Int? = {
            guard let pages = dto.pages, let read = dto.pagesRead else { return nil }
            return max(0, pages - read)
        }()
        let title = (dto.localizedName?.isEmpty == false ? dto.localizedName : nil) ?? dto.name
        return SeriesSummary(ref: ref(dto.id), title: title, coverURL: coverURL(seriesID: dto.id),
                             unreadCount: unread, libraryID: dto.libraryId.map(String.init),
                             pageCount: dto.pages, pagesRead: dto.pagesRead,
                             format: ContentFormat(kavitaFormat: dto.format))
    }

    func coverURL(seriesID: Int) -> URL? {
        try? anonymous.url("api/Image/series-cover", query: ["seriesId": String(seriesID), "apiKey": apiKey])
    }

    func pageURL(chapterID: String, page: Int) throws -> URL {
        try anonymous.url("api/Reader/image", query: ["chapterId": chapterID, "page": String(page),
                                                      "apiKey": apiKey, "extractPdf": "true"])
    }

    /// Flattens Kavita volumes into one reading-ordered chapter list:
    /// numbered volumes first, then loose chapters, then specials.
    /// `seriesFormat` is used for chapters whose files don't say.
    static func chapters(from volumes: [KavitaVolumeDTO], seriesRef: SeriesRef,
                         seriesFormat: ContentFormat? = nil) -> [Chapter] {
        func volumeRank(_ v: KavitaVolumeDTO) -> (Int, Double) {
            let n = v.minNumber ?? 0
            if n <= looseLeafVolumeNumber { return (1, 0) }
            if n >= specialVolumeNumber { return (2, 0) }
            return (0, n)
        }
        let sorted = volumes.sorted { volumeRank($0) < volumeRank($1) }
        var result: [Chapter] = []
        var sequence = 0.0
        for volume in sorted {
            let rank = volumeRank(volume)
            let chapters = (volume.chapters ?? []).sorted { ($0.sortOrder ?? $0.minNumber ?? 0) < ($1.sortOrder ?? $1.minNumber ?? 0) }
            for dto in chapters {
                let pages = dto.pages ?? 0
                let read = dto.pagesRead ?? 0
                let title = chapterTitle(dto, volume: volume, volumeRank: rank.0)
                sequence += 1
                result.append(Chapter(
                    id: String(dto.id),
                    seriesRef: seriesRef,
                    volumeID: String(dto.volumeId ?? volume.id),
                    title: title,
                    number: sequence,
                    pageCount: pages,
                    lastPageRead: max(0, min(read, max(pages - 1, 0))),
                    isRead: pages > 0 && read >= pages,
                    updatedAt: dto.lastModifiedUtc ?? dto.created,
                    format: dto.files?.lazy.compactMap { ContentFormat(kavitaFormat: $0.format) }.first ?? seriesFormat,
                    lastReadAt: read > 0 ? realDate(dto.lastReadingProgressUtc) : nil
                ))
            }
        }
        return result
    }

    /// Kavita sends `0001-01-01T00:00:00` for "never".
    static func realDate(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSince1970 > 86_400 else { return nil }
        return date
    }

    static func chapterTitle(_ dto: KavitaChapterDTO, volume: KavitaVolumeDTO, volumeRank: Int) -> String {
        if let name = dto.titleName, !name.isEmpty {
            if let range = dto.range, !range.isEmpty, dto.isSpecial != true, (dto.minNumber ?? 0) > looseLeafVolumeNumber,
               !name.localizedCaseInsensitiveContains(range) {
                return "Chapter \(range): \(name)"
            }
            return name
        }
        if dto.isSpecial == true || volumeRank == 2 {
            return dto.title?.isEmpty == false ? dto.title! : (dto.range ?? "Special")
        }
        let chapterNumber = dto.minNumber ?? 0
        if chapterNumber <= looseLeafVolumeNumber {
            // A volume file with no chapter split.
            return "Volume \(volume.name ?? String(format: "%g", volume.minNumber ?? 0))"
        }
        return "Chapter \(dto.range ?? String(format: "%g", chapterNumber))"
    }
}

struct EmptyBody: Encodable {}

actor TokenCache {
    private(set) var token: String?
    /// True once the server turned the `x-api-key` header down.
    private(set) var usesJWT = false
    func set(_ token: String) { self.token = token }
    func clear() { token = nil }
    func useJWT() { usesJWT = true }
}
