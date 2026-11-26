import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class ContentFilterTests: XCTestCase {
    func testInactiveByDefault() {
        XCTAssertFalse(ContentFilter().isActive)
        XCTAssertFalse(ContentFilter.none.hides(genres: ["Horror"], tags: ["Gore"], ageRating: .x18Plus))
        XCTAssertEqual(ContentFilter.none.cacheKey, "none")
        XCTAssertEqual(ContentFilter.none.summary, "Everything is shown")
    }

    func testGenresMatchIgnoringCaseAccentsAndSpaces() {
        let f = ContentFilter(hiddenGenres: ["Horror", " Écchi "])
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.hides(genres: ["Action", "horror"]))
        XCTAssertTrue(f.hides(genres: ["ECCHI"]))
        XCTAssertFalse(f.hides(genres: ["Action", "Comedy"]))
        XCTAssertFalse(f.hides(genres: []))
        XCTAssertTrue(f.isGenreHidden("HORROR"))
    }

    func testTags() {
        let f = ContentFilter(hiddenTags: ["Gore"])
        XCTAssertTrue(f.hides(genres: [], tags: ["gore"]))
        XCTAssertFalse(f.hides(genres: ["Gore"], tags: []), "a tag filter doesn't match genres")
    }

    func testAgeLimit() {
        let f = ContentFilter(maxAgeRating: .teen)
        XCTAssertFalse(f.hides(genres: [], ageRating: .everyone))
        XCTAssertFalse(f.hides(genres: [], ageRating: .teen))
        XCTAssertTrue(f.hides(genres: [], ageRating: .mature17Plus))
        XCTAssertTrue(f.hides(genres: [], ageRating: .x18Plus))
        // Unrated shows unless asked otherwise.
        XCTAssertFalse(f.hides(genres: [], ageRating: .unknown))
        XCTAssertFalse(f.hides(genres: [], ageRating: nil))
        XCTAssertFalse(f.hides(genres: [], ageRating: .notApplicable))
        // Servers without ratings ignore the limit.
        XCTAssertFalse(f.hides(genres: [], ageRating: .x18Plus, supportsAgeRating: false))
    }

    func testHideUnrated() {
        let f = ContentFilter(maxAgeRating: .teen, hideUnrated: true)
        XCTAssertTrue(f.hides(genres: [], ageRating: .unknown))
        XCTAssertTrue(f.hides(genres: [], ageRating: .ratingPending))
        XCTAssertTrue(f.hides(genres: [], ageRating: nil))
        XCTAssertFalse(f.hides(genres: [], ageRating: .everyone))
        // Without a limit, hideUnrated alone does nothing.
        XCTAssertFalse(ContentFilter(hideUnrated: true).isActive)
    }

    func testSetGenreKeepsOneEntryPerName() {
        var f = ContentFilter()
        f.setGenre("Horror", hidden: true)
        f.setGenre("horror ", hidden: true)
        XCTAssertEqual(f.hiddenGenres.count, 1)
        f.setGenre("HORROR", hidden: false)
        XCTAssertTrue(f.hiddenGenres.isEmpty)
        f.setTag("Gore", hidden: true)
        XCTAssertEqual(f.hiddenTags, ["Gore"])
        f.setGenre("   ", hidden: true)
        XCTAssertTrue(f.hiddenGenres.isEmpty)
    }

    func testCacheKeyIgnoresOrderAndCase() {
        let a = ContentFilter(hiddenGenres: ["Horror", "Ecchi"], maxAgeRating: .teen)
        let b = ContentFilter(hiddenGenres: ["ecchi", "HORROR"], maxAgeRating: .teen)
        XCTAssertEqual(a.cacheKey, b.cacheKey)
        XCTAssertNotEqual(a.cacheKey, ContentFilter(hiddenGenres: ["Horror"], maxAgeRating: .teen).cacheKey)
        XCTAssertNotEqual(a.cacheKey, ContentFilter(hiddenGenres: ["Horror", "Ecchi"], maxAgeRating: .teen, hideUnrated: true).cacheKey)
    }

    func testSummary() {
        XCTAssertEqual(ContentFilter(hiddenGenres: ["A", "B"], hiddenTags: ["C"], maxAgeRating: .teen).summary,
                       "Hides 2 genres, 1 tag · Up to Teen")
        XCTAssertEqual(ContentFilter(hiddenGenres: ["A"]).summary, "Hides 1 genre")
    }

    func testCodableRoundTrip() throws {
        let f = ContentFilter(hiddenGenres: ["Horror"], hiddenTags: ["Gore"], maxAgeRating: .mature15Plus, hideUnrated: true)
        let back = try JSONDecoder().decode(ContentFilter.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }

    func testFacetsMergeDedupesAndKeepsHidden() {
        let a = ContentFacets(genres: ["Action", "horror"], tags: ["Gore"], supportsAgeRating: true)
        let b = ContentFacets(genres: ["Horror", "Comedy"], tags: [], supportsAgeRating: false)
        let merged = ContentFacets.merged([a, b], keeping: ContentFilter(hiddenGenres: ["Gone"], hiddenTags: ["gore"]))
        XCTAssertEqual(merged.genres, ["Action", "Comedy", "Gone", "horror"])
        XCTAssertEqual(merged.tags, ["Gore"])
        XCTAssertTrue(merged.supportsAgeRating)
    }

    func testVisibilityFailsClosed() {
        let s1 = UUID(), s2 = UUID()
        let series = [SeriesSummary(ref: SeriesRef(serverID: s1, seriesID: "1"), title: "A", coverURL: nil),
                      SeriesSummary(ref: SeriesRef(serverID: s1, seriesID: "2"), title: "B", coverURL: nil),
                      SeriesSummary(ref: SeriesRef(serverID: s2, seriesID: "1"), title: "C", coverURL: nil)]
        let filter = ContentFilter(hiddenGenres: ["Horror"])
        XCTAssertEqual(ContentVisibility.visible(series, filter: .none, hidden: [:]).count, 3)
        let shown = ContentVisibility.visible(series, filter: filter, hidden: [s1: ["2"]])
        XCTAssertEqual(shown.map(\.title), ["A"], "s2's hidden ids aren't known, so its series stay hidden")
    }
}

final class AppStateContentFilterTests: XCTestCase {
    func testFilterIsPerProfileAndPersists() throws {
        var s = AppState.initial()
        let me = s.activeProfile!.id
        let kid = s.addProfile(name: "Kid").id
        s.setContentFilter(ContentFilter(hiddenGenres: ["Horror"], maxAgeRating: .teen), profile: kid)
        s.setRequiresPINToOpen(true, profile: me)
        XCTAssertFalse(s.contentFilter(profile: me).isActive)
        XCTAssertEqual(s.contentFilter(profile: kid).maxAgeRating, .teen)

        let store = StateStore(backing: InMemoryKeyValueStore())
        store.save(s)
        let back = store.load()
        XCTAssertEqual(back.contentFilter(profile: kid), s.contentFilter(profile: kid))
        XCTAssertTrue(back.requiresPINToOpen(profile: me))
        XCTAssertFalse(back.requiresPINToOpen(profile: kid))

        // Clearing stores nothing.
        s.setContentFilter(.none, profile: kid)
        XCTAssertNil(s.profileData[kid.uuidString]?.contentFilter)
    }

    func testOldStateWithoutFiltersDecodes() throws {
        let json = #"{"serverSettings":{},"favorites":[],"progress":{},"defaultReaderSettings":\#(String(decoding: try JSONEncoder().encode(ReaderSettings.default), as: UTF8.self)),"readerOverrides":{}}"#
        let data = try JSONDecoder().decode(ProfileData.self, from: Data(json.utf8))
        XCTAssertNil(data.contentFilter)
        XCTAssertNil(data.requiresPINToOpen)
    }

    func testVisibleFavoritesApplyFilter() {
        var s = AppState.initial()
        let me = s.activeProfile!.id
        let server = ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://k")!)
        s.addServer(server)
        for id in ["1", "2", "3"] {
            s.setFavorite(SeriesSummary(ref: SeriesRef(serverID: server.id, seriesID: id), title: id, coverURL: nil),
                          true, profile: me)
        }
        XCTAssertEqual(s.visibleFavorites(profile: me, hidden: [:]).count, 3, "no filter, nothing hidden")
        s.setContentFilter(ContentFilter(hiddenGenres: ["Horror"]), profile: me)
        XCTAssertEqual(s.visibleFavorites(profile: me, hidden: [:]).count, 0, "fails closed until ids load")
        XCTAssertEqual(Set(s.visibleFavorites(profile: me, hidden: [server.id: ["2"]]).map(\.series.ref.seriesID)), ["1", "3"])
    }
}

/// Counts calls so caching can be checked.
private final class CountingServer: MangaServer, @unchecked Sendable {
    let inner: SampleLibraryServer
    private let lock = NSLock()
    private var _hiddenCalls = 0
    var hiddenCalls: Int { lock.withLock { _hiddenCalls } }
    var failHidden = false

    init(seriesCount: Int = 90, kind: ServerKind = .kavita) {
        inner = SampleLibraryServer(config: ServerConfig(kind: kind, name: "Demo", baseURL: URL(string: "https://demo.invalid")!),
                                    seriesCount: seriesCount, latency: .zero)
    }

    var config: ServerConfig { inner.config }
    func validate() async throws -> String { try await inner.validate() }
    func categories() async throws -> [MangaCategory] { try await inner.categories() }
    func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        try await inner.series(in: category, page: page, pageSize: pageSize)
    }
    private var _sorts: [LibrarySort] = []
    var sorts: [LibrarySort] { lock.withLock { _sorts } }
    func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary> {
        lock.withLock { _sorts.append(sort) }
        return try await inner.series(in: category, page: page, pageSize: pageSize, sort: sort)
    }
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] { try await inner.feed(feed, limit: limit) }
    func search(_ query: String) async throws -> [SeriesSummary] { try await inner.search(query) }
    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail { try await inner.seriesDetail(seriesID) }
    func pages(for chapter: Chapter) async throws -> [PageDescriptor] { try await inner.pages(for: chapter) }
    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}
    func markUnread(chapters: [Chapter]) async throws {}
    func markSeriesUnread(_ seriesID: String) async throws {}
    func authorize(_ request: URLRequest) -> URLRequest { request }
    func contentFacets() async throws -> ContentFacets { try await inner.contentFacets() }
    func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        lock.withLock { _hiddenCalls += 1 }
        if failHidden { throw MangaError.http(status: 500, body: "") }
        return try await inner.hiddenSeriesIDs(for: filter)
    }
}

final class ContentFilteredServerTests: XCTestCase {
    let horror = ContentFilter(hiddenGenres: ["Horror"]) // multiples of 5

    func testInactiveFilterReturnsClientItself() {
        let base = CountingServer()
        XCTAssertTrue((ContentFilteredServer.wrapping(base, filter: .none) as AnyObject) === base)
        XCTAssertTrue(ContentFilteredServer.wrapping(base, filter: horror) is ContentFilteredServer)
    }

    func testSearchDropsHiddenSeries() async throws {
        let server = ContentFilteredServer(base: CountingServer(), filter: horror)
        // "Lantern" matches 3, 11, 19, 27, 35, 43, 51, 59, 67, 75, 83.
        let results = try await server.search("Lantern")
        XCTAssertEqual(results.count, 9)
        XCTAssertFalse(results.contains { $0.ref.seriesID == "35" || $0.ref.seriesID == "75" })
    }

    func testFeedStaysFullAfterFiltering() async throws {
        let server = ContentFilteredServer(base: CountingServer(), filter: horror)
        let row = try await server.feed(.recentlyUpdated, limit: 10)
        XCTAssertEqual(row.count, 10)
        XCTAssertFalse(row.contains { Int($0.ref.seriesID)! % 5 == 0 })
    }

    func testLibraryPagesSkipFullyHiddenPages() async throws {
        // Everything is hidden, so every page comes back empty.
        let filter = ContentFilter(hiddenGenres: ["Adventure"])
        let base = CountingServer(seriesCount: 4)
        let server = ContentFilteredServer(base: base, filter: filter)
        let page = try await server.series(in: MangaCategory(id: "all", name: "All"), page: 1, pageSize: 2)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertFalse(page.hasMore)

        // A page with one hidden and one shown series keeps just the shown one.
        let plain = CountingServer(seriesCount: 12)
        let some = ContentFilteredServer(base: plain, filter: ContentFilter(hiddenGenres: ["Horror"]))
        let all = MangaCategory(id: "all", name: "All")
        let isHorror = { (s: SeriesSummary) in Int(s.ref.seriesID)! % 5 == 0 }
        var mixedPage: Int?
        for n in 1...6 {
            let items = try await plain.series(in: all, page: n, pageSize: 2).items
            if items.contains(where: isHorror) && !items.allSatisfy(isHorror) { mixedPage = n; break }
        }
        let n = try XCTUnwrap(mixedPage, "the demo library should have a page with series 5 or 10 beside another")
        let expected = try await plain.series(in: all, page: n, pageSize: 2).items.filter { !isHorror($0) }
        let filtered = try await some.series(in: all, page: n, pageSize: 2)
        XCTAssertEqual(filtered.items.map(\.ref.seriesID), expected.map(\.ref.seriesID))
        XCTAssertEqual(filtered.items.count, 1)
    }

    func testSortedPagesKeepTheSortAndFilter() async throws {
        let base = CountingServer(seriesCount: 12)
        let server = ContentFilteredServer(base: base, filter: horror)
        let page = try await server.series(in: MangaCategory(id: "all", name: "All"), page: 1, pageSize: 12,
                                           sort: .recentlyAdded)
        XCTAssertEqual(base.sorts, [.recentlyAdded], "the sort didn't reach the server")
        XCTAssertEqual(page.items.count, 10)
        XCTAssertFalse(page.items.contains { $0.ref.seriesID == "5" || $0.ref.seriesID == "10" })
    }

    func testUnfilteredReachesTheClientForCapabilities() {
        let base = CountingServer()
        let wrapped = ContentFilteredServer.wrapping(base, filter: horror)
        XCTAssertTrue((wrapped.unfiltered as AnyObject) === base)
        XCTAssertTrue((base.unfiltered as AnyObject) === base)
    }

    func testDetailOfHiddenSeriesIsNotFound() async throws {
        let server = ContentFilteredServer(base: CountingServer(), filter: horror)
        _ = try await server.seriesDetail("4")
        do {
            _ = try await server.seriesDetail("5")
            XCTFail("hidden series opened")
        } catch {
            XCTAssertEqual(error as? MangaError, .notFound)
        }
    }

    func testHiddenIDsAreCachedAndShared() async throws {
        let base = CountingServer()
        let server = ContentFilteredServer(base: base, filter: horror)
        async let a = server.search("Ember")
        async let b = server.feed(.newlyAdded, limit: 5)
        _ = try await (a, b)
        _ = try await server.search("Harbor")
        XCTAssertEqual(base.hiddenCalls, 1)

        let expiring = ContentFilteredServer(base: base, filter: horror, ttl: 0)
        _ = try await expiring.search("Ember")
        _ = try await expiring.search("Ember")
        XCTAssertEqual(base.hiddenCalls, 3)
    }

    func testFailsClosedWhenHiddenIDsFail() async {
        let base = CountingServer()
        base.failHidden = true
        let server = ContentFilteredServer(base: base, filter: horror)
        do {
            _ = try await server.search("Lantern")
            XCTFail("unfiltered results were returned")
        } catch {}
    }

    func testDemoServerAgeRatingsOnlyOnKavita() async throws {
        let limit = ContentFilter(maxAgeRating: .teen) // hides multiples of 7
        let kavita = try await CountingServer(kind: .kavita).hiddenSeriesIDs(for: limit)
        XCTAssertTrue(kavita.contains("7"))
        XCTAssertFalse(kavita.contains("11"), "unrated shows by default")
        let suwayomi = try await CountingServer(kind: .suwayomi).hiddenSeriesIDs(for: limit)
        XCTAssertTrue(suwayomi.isEmpty)
    }

    func testDefaultImplementationFailsClosed() async throws {
        struct Bare: MangaServer {
            var config = ServerConfig(kind: .kavita, name: "B", baseURL: URL(string: "http://b")!)
            func validate() async throws -> String { "" }
            func categories() async throws -> [MangaCategory] { [] }
            func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> { Paged(items: [], hasMore: false) }
            func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] { [] }
            func search(_ query: String) async throws -> [SeriesSummary] { [] }
            func seriesDetail(_ seriesID: String) async throws -> SeriesDetail { throw MangaError.notFound }
            func pages(for chapter: Chapter) async throws -> [PageDescriptor] { [] }
            func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}
            func markUnread(chapters: [Chapter]) async throws {}
            func markSeriesUnread(_ seriesID: String) async throws {}
            func authorize(_ request: URLRequest) -> URLRequest { request }
        }
        let none = try await Bare().hiddenSeriesIDs(for: .none)
        XCTAssertTrue(none.isEmpty)
        do {
            _ = try await Bare().hiddenSeriesIDs(for: horror)
            XCTFail("expected an error")
        } catch {}
    }
}

final class KavitaContentFilterTests: XCTestCase {
    let config = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
    var mock: MockTransport!

    override func setUp() {
        mock = MockTransport()
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"john","token":"jwt-1"}"#)
        mock.on("GET", "api/Metadata/genres", body: #"[{"id":4,"title":"Horror"},{"id":9,"title":"Comedy"},{"id":12,"title":"horror "}]"#)
        mock.on("GET", "api/Metadata/tags", body: #"[{"id":2,"title":"Gore"}]"#)
        mock.on("POST", "api/Series/v2", body: #"[{"id":31,"name":"A"},{"id":32,"name":"B"}]"#)
    }

    var client: KavitaClient { KavitaClient(config: config, apiKey: "KEY", transport: mock) }

    func testFacets() async throws {
        let facets = try await client.contentFacets()
        XCTAssertEqual(facets.genres, ["Horror", "Comedy", "horror "])
        XCTAssertEqual(facets.tags, ["Gore"])
        XCTAssertTrue(facets.supportsAgeRating)
    }

    func testHiddenIDsSendOneOrFilter() async throws {
        let filter = ContentFilter(hiddenGenres: ["HORROR"], hiddenTags: ["gore", "Missing"], maxAgeRating: .teen, hideUnrated: true)
        let ids = try await client.hiddenSeriesIDs(for: filter)
        XCTAssertEqual(ids, ["31", "32"])

        let request = try XCTUnwrap(mock.lastRequest(containing: "api/Series/v2"))
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("pageSize=500"), url)
        XCTAssertTrue(url.contains("pageNumber=1"), url)
        let body = jsonBody(request)
        XCTAssertEqual(body["combination"] as? Int, 0, "statements are or-ed")
        let statements = try XCTUnwrap(body["statements"] as? [[String: Any]])
        let pairs = statements.map { "\($0["field"] as! Int)/\($0["comparison"] as! Int)/\($0["value"] as! String)" }
        XCTAssertEqual(pairs, ["18/5/4,12", "6/5/2", "4/1/8", "4/4/1"])
    }

    func testNothingToMatchSkipsTheQuery() async throws {
        let none = try await client.hiddenSeriesIDs(for: .none)
        XCTAssertTrue(none.isEmpty)
        XCTAssertTrue(mock.requests.isEmpty, "an inactive filter costs nothing")
        let ids = try await client.hiddenSeriesIDs(for: ContentFilter(hiddenGenres: ["Not On Server"]))
        XCTAssertTrue(ids.isEmpty)
        XCTAssertNil(mock.lastRequest(containing: "api/Series/v2"))
    }

    func testAgeOnlyDoesNotFetchGenres() async throws {
        _ = try await client.hiddenSeriesIDs(for: ContentFilter(maxAgeRating: .everyone))
        XCTAssertNil(mock.lastRequest(containing: "api/Metadata/genres"))
        let statements = try XCTUnwrap(jsonBody(mock.lastRequest(containing: "api/Series/v2"))["statements"] as? [[String: Any]])
        XCTAssertEqual(statements.count, 1)
        XCTAssertEqual(statements[0]["value"] as? String, "3")
    }
}

final class SuwayomiContentFilterTests: XCTestCase {
    let config = ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://suwayomi.local:4567")!)

    func testFacetsAndHiddenIDsUseGenres() async throws {
        let mock = MockTransport()
        mock.onGraphQL("nodes { id genre }", body: #"{"data":{"mangas":{"nodes":[{"id":1,"genre":["Action","Horror"]},{"id":2,"genre":["action"," Comedy"]},{"id":3,"genre":[]},{"id":4}]}}}"#)
        let client = SuwayomiClient(config: config, username: nil, password: nil, transport: mock)

        let facets = try await client.contentFacets()
        XCTAssertEqual(facets.genres, ["Action", "Comedy", "Horror"])
        XCTAssertFalse(facets.supportsAgeRating)

        let hidden = try await client.hiddenSeriesIDs(for: ContentFilter(hiddenGenres: ["horror", "Comedy"]))
        XCTAssertEqual(hidden, ["1", "2"])

        // Age limits and tags don't apply, and don't cost a request.
        let before = mock.requests.count
        let none = try await client.hiddenSeriesIDs(for: ContentFilter(hiddenTags: ["Gore"], maxAgeRating: .teen))
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(mock.requests.count, before)
    }
}
