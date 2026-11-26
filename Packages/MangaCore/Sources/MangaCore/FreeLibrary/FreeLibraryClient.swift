import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `MangaServer` for the built-in Free Library. Series come from the
/// curated `FreeLibraryCatalog`; Internet Archive pages come from IIIF
/// manifests and Pepper&Carrot episodes from peppercarrot.com.
///
/// There's no account and no server-side progress: progress is kept on the
/// Apple TV like any profile that doesn't sync (`AppModel.syncsProgress`).
public final class FreeLibraryClient: MangaServer {
    public let config: ServerConfig
    /// Collection ids to show; nil shows all.
    public let categoryScope: Set<String>?
    let transport: HTTPTransport
    let store: FreeLibraryStore

    public init(config: ServerConfig = FreeLibrary.config, categoryScope: Set<String>? = nil,
                transport: HTTPTransport = URLSessionTransport(), store: FreeLibraryStore = .shared) {
        self.config = config
        self.categoryScope = categoryScope
        self.transport = transport
        self.store = store
    }

    // MARK: Catalog

    func catalog() async -> FreeLibraryCatalog {
        await store.catalog(transport: transport)
    }

    private func visibleSeries(_ catalog: FreeLibraryCatalog) -> [FreeLibraryCatalog.Series] {
        catalog.series.filter { categoryScope?.contains($0.collection) ?? true }
    }

    func ref(_ id: String) -> SeriesRef { SeriesRef(serverID: config.id, seriesID: id) }

    func summary(_ s: FreeLibraryCatalog.Series) -> SeriesSummary {
        SeriesSummary(ref: ref(s.id), title: s.title, coverURL: coverURL(s), libraryID: s.collection,
                      chapterCount: s.chapters.flatMap { $0.isEmpty ? nil : $0.count })
    }

    func coverURL(_ s: FreeLibraryCatalog.Series) -> URL? {
        switch s.source {
        case .internetArchive:
            guard let id = s.cover ?? s.chapters?.first?.identifier else { return nil }
            return URL(string: "https://archive.org/services/img/\(id)")
        case .pepperCarrot:
            return PepperCarrot.seriesCoverURL
        }
    }

    // MARK: MangaServer

    public func validate() async throws -> String {
        let catalog = await catalog()
        return "\(catalog.series.count) free titles"
    }

    public func categories() async throws -> [MangaCategory] {
        let catalog = await catalog()
        let used = Set(catalog.series.map(\.collection))
        return catalog.collections.enumerated()
            .filter { used.contains($0.element.id) && (categoryScope?.contains($0.element.id) ?? true) }
            .map { MangaCategory(id: $0.element.id, name: $0.element.name, order: $0.offset) }
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        let all = visibleSeries(await catalog()).filter { $0.collection == category.id }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let start = max(0, (page - 1) * pageSize)
        guard start < all.count else { return Paged(items: [], hasMore: false) }
        let end = min(all.count, start + pageSize)
        return Paged(items: all[start..<end].map(summary), hasMore: end < all.count)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        let series = visibleSeries(await catalog())
        switch feed {
        case .continueReading:
            // Progress is local; the app's own rows show it.
            return []
        case .recentlyUpdated:
            // Only Pepper&Carrot gets new chapters.
            return Array(series.filter { $0.source == .pepperCarrot }.map(summary).prefix(limit))
        case .newlyAdded:
            let sorted = series.enumerated().sorted {
                $0.element.added != $1.element.added ? $0.element.added > $1.element.added : $0.offset < $1.offset
            }.map(\.element)
            return Array(sorted.map(summary).prefix(limit))
        }
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return visibleSeries(await catalog()).filter { s in
            ([s.title] + s.creators).contains { $0.range(of: q, options: options) != nil }
        }.map(summary)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        guard let s = await catalog().series.first(where: { $0.id == seriesID }) else { throw MangaError.notFound }
        let chapters: [Chapter]
        switch s.source {
        case .internetArchive:
            chapters = (s.chapters ?? []).enumerated().map { i, c in
                Chapter(id: Self.iaChapterPrefix + c.identifier, seriesRef: ref(s.id), title: c.title,
                        number: Double(i + 1), pageCount: c.pages ?? 0)
            }
        case .pepperCarrot:
            chapters = try await pepperCarrotEpisodes().map { $0.chapter(seriesRef: ref(s.id)) }
        }
        return SeriesDetail(summary: summary(s), synopsis: Self.synopsis(for: s), authors: s.creators,
                            genres: s.genres ?? [], status: "\(s.license.displayName) · \(s.published)",
                            chapters: chapters)
    }

    /// The catalog's description followed by the credit and license, which
    /// CC BY requires to be visible.
    static func synopsis(for s: FreeLibraryCatalog.Series) -> String {
        switch s.source {
        case .internetArchive:
            return "\(s.synopsis)\n\n\(s.rights) Scans from the Internet Archive (archive.org)."
        case .pepperCarrot:
            return "\(s.synopsis)\n\n\(PepperCarrot.credit)"
        }
    }

    static let iaChapterPrefix = "ia:"

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        if let cached = await store.cachedPages(chapter.id) { return cached }
        let pages: [PageDescriptor]
        if chapter.id.hasPrefix(Self.iaChapterPrefix) {
            let identifier = String(chapter.id.dropFirst(Self.iaChapterPrefix.count))
            pages = try await iiifPages(identifier)
        } else if let episode = PepperCarrotEpisode.name(fromChapterID: chapter.id) {
            guard let match = try await pepperCarrotEpisodes().first(where: { $0.name == episode }) else {
                throw MangaError.notFound
            }
            pages = match.pages()
        } else {
            throw MangaError.notFound
        }
        guard !pages.isEmpty else { throw MangaError.decoding("No pages in \(chapter.title)") }
        await store.storePages(pages, for: chapter.id)
        return pages
    }

    func iiifPages(_ identifier: String) async throws -> [PageDescriptor] {
        guard FreeLibraryCatalog.isValidIdentifier(identifier),
              let url = URL(string: "https://iiif.archive.org/iiif/3/\(identifier)/manifest.json") else {
            throw MangaError.invalidURL(identifier)
        }
        let data = try await get(url)
        let manifest = try HTTPClient.decode(IIIFManifest.self, from: data)
        return manifest.pages()
    }

    func pepperCarrotEpisodes() async throws -> [PepperCarrotEpisode] {
        if let cached = await store.cachedEpisodes() { return cached }
        let data = try await get(PepperCarrot.episodesURL)
        let episodes = try PepperCarrot.parseEpisodes(data)
        await store.storeEpisodes(episodes)
        return episodes
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await HTTPClient(baseURL: url, transport: transport).send(request)
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}

    // Progress lives only in AppState for the Free Library, so there is
    // nothing to clear on a server.
    public func markUnread(chapters: [Chapter]) async throws {}

    public func markSeriesUnread(_ seriesID: String) async throws {}

    public func authorize(_ request: URLRequest) -> URLRequest { request }
}
