import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Kavita's REST API. Logs in with the user's API key through the
/// plugin endpoint, then uses the returned JWT for API calls. Image URLs carry
/// the API key as a query parameter, which Kavita accepts for images.
public final class KavitaClient: MangaServer, @unchecked Sendable {
    public let config: ServerConfig
    let apiKey: String
    let transport: HTTPTransport
    /// Library ids to show; nil shows every library.
    public let categoryScope: Set<String>?
    private let tokenCache = TokenCache()

    public static let pluginName = "AppleTVMangaReader"

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

    // MARK: Auth

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

    /// Runs a call, logging in again once if the cached token has expired.
    func withAuth<T>(_ body: (HTTPClient) async throws -> T) async throws -> T {
        do {
            return try await body(try await authed())
        } catch MangaError.unauthorized {
            await tokenCache.clear()
            return try await body(try await authed())
        }
    }

    // MARK: MangaServer

    public func validate() async throws -> String {
        let user = try await login()
        return "Signed in to Kavita as \(user.username ?? "user")"
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

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        guard let chapterID = Int(chapter.id),
              let seriesID = Int(chapter.seriesRef.seriesID),
              let volumeID = chapter.volumeID.flatMap(Int.init),
              let libraryID = libraryID.flatMap(Int.init) else {
            throw MangaError.notFound
        }
        let body = KavitaProgressDTO(volumeId: volumeID, chapterId: chapterID,
                                     pageNum: completed ? chapter.pageCount : max(0, page),
                                     seriesId: seriesID, libraryId: libraryID)
        try await withAuth { try await $0.postIgnoringResponse("api/Reader/progress", body: body) }
    }

    /// One call for any number of chapters (`mark-multiple-read`), which
    /// needs no volume or library id.
    public func markRead(chapters: [Chapter], libraryID: String?) async throws {
        guard let body = try markMultipleBody(chapters) else { return }
        try await withAuth { try await $0.postIgnoringResponse("api/Reader/mark-multiple-read", body: body) }
    }

    private func markMultipleBody(_ chapters: [Chapter]) throws -> KavitaMarkMultipleDTO? {
        guard let first = chapters.first else { return nil }
        guard let seriesID = Int(first.seriesRef.seriesID) else { throw MangaError.notFound }
        let ids = try chapters.map { chapter -> Int in
            guard let id = Int(chapter.id), chapter.seriesRef == first.seriesRef else { throw MangaError.notFound }
            return id
        }
        return KavitaMarkMultipleDTO(seriesId: seriesID, volumeIds: [], chapterIds: ids)
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
                    format: dto.files?.lazy.compactMap { ContentFormat(kavitaFormat: $0.format) }.first ?? seriesFormat
                ))
            }
        }
        return result
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
    func set(_ token: String) { self.token = token }
    func clear() { token = nil }
}
