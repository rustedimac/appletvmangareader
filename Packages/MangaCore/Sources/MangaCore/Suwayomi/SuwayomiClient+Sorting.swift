import Foundation

/// Library grids. Suwayomi returns a whole category at once, so the client
/// sorts and pages it. Page 1 fetches the category; later pages reuse that
/// answer for a few minutes so scrolling a 700-manga category doesn't
/// download it again for every page.
extension SuwayomiClient {
    /// Extra fields for sorting and badges. `lastReadChapter` is
    /// deprecated in newer servers but still answers; if a server rejects
    /// any of these, the grid falls back to the basic fields.
    static let gridFields = SuwayomiMangaDTO.fields
        + " inLibraryAt chapters { totalCount } latestFetchedChapter { fetchedAt } lastReadChapter { lastReadAt }"

    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary> {
        guard let id = Int(category.id) else { throw MangaError.notFound }
        let all: [SuwayomiGridManga]
        if page > 1, let cached = await gridCache.get(categoryID: id) {
            all = cached
        } else {
            all = try await fetchGrid(categoryID: id)
            await gridCache.set(all, categoryID: id)
        }
        var dates: [SeriesRef: Date] = [:]
        var summaries: [SeriesSummary] = []
        for m in all where m.manga.inLibrary != false {
            let s = summary(m)
            summaries.append(s)
            if let date = m.date(for: sort) { dates[s.ref] = date }
        }
        let sorted = summaries.sorted(by: sort, dates: dates)
        let start = max(0, (page - 1) * pageSize)
        guard start < sorted.count else { return Paged(items: [], hasMore: false) }
        let end = min(sorted.count, start + pageSize)
        return Paged(items: Array(sorted[start..<end]), hasMore: end < sorted.count)
    }

    func fetchGrid(categoryID id: Int) async throws -> [SuwayomiGridManga] {
        struct Response: Decodable {
            struct Category: Decodable { var mangas: Nodes<SuwayomiGridManga> }
            var category: Category
        }
        let query = { (fields: String) in "query($id: Int!) { category(id: $id) { mangas { nodes { \(fields) } } } }" }
        do {
            let r: Response = try await graphQL(query(Self.gridFields), variables: ["id": .int(id)])
            return r.category.mangas.nodes
        } catch let error as MangaError {
            // A server that doesn't know an extra field answers with a
            // GraphQL error (or HTTP 400); ask again without them.
            switch error {
            case .graphQL, .http(status: 400, body: _): break
            default: throw error
            }
            let r: Response = try await graphQL(query(SuwayomiMangaDTO.fields), variables: ["id": .int(id)])
            return r.category.mangas.nodes
        }
    }
}

/// A manga with the grid's extra fields. Every extra is optional.
struct SuwayomiGridManga: Decodable, @unchecked Sendable {
    struct ChapterCount: Decodable { var totalCount: Int? }
    struct Fetched: Decodable { var fetchedAt: FlexibleNumber? }
    struct Read: Decodable { var lastReadAt: FlexibleNumber? }

    var manga: SuwayomiMangaDTO
    var inLibraryAt: FlexibleNumber?
    var chapters: ChapterCount?
    var latestFetchedChapter: Fetched?
    var lastReadChapter: Read?

    private enum CodingKeys: String, CodingKey { case inLibraryAt, chapters, latestFetchedChapter, lastReadChapter }

    init(from decoder: Decoder) throws {
        manga = try SuwayomiMangaDTO(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inLibraryAt = try? c.decodeIfPresent(FlexibleNumber.self, forKey: .inLibraryAt)
        chapters = try? c.decodeIfPresent(ChapterCount.self, forKey: .chapters)
        latestFetchedChapter = try? c.decodeIfPresent(Fetched.self, forKey: .latestFetchedChapter)
        lastReadChapter = try? c.decodeIfPresent(Read.self, forKey: .lastReadChapter)
    }

    var chapterCount: Int? { chapters?.totalCount }

    /// The date `sort` orders by. Suwayomi timestamps are seconds (some
    /// builds send milliseconds); zero means never.
    func date(for sort: LibrarySort) -> Date? {
        let raw: Double?
        switch sort {
        case .recentlyAdded: raw = inLibraryAt?.value
        case .recentlyUpdated: raw = latestFetchedChapter?.fetchedAt?.value
        case .recentlyRead: raw = lastReadChapter?.lastReadAt?.value
        case .titleAscending, .titleDescending: raw = nil
        }
        guard let raw, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 1e11 ? raw / 1000 : raw)
    }
}

/// The last category a grid loaded, so pages 2+ don't refetch it.
actor SuwayomiGridCache {
    private var categoryID: Int?
    private var items: [SuwayomiGridManga] = []
    private var storedAt = Date.distantPast
    let lifetime: TimeInterval = 300

    func get(categoryID id: Int) -> [SuwayomiGridManga]? {
        guard categoryID == id, Date().timeIntervalSince(storedAt) < lifetime else { return nil }
        return items
    }

    func set(_ items: [SuwayomiGridManga], categoryID id: Int) {
        categoryID = id
        self.items = items
        storedAt = Date()
    }
}
