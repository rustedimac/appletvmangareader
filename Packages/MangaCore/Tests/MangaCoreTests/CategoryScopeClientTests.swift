import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Clients limited to some Kavita libraries / Suwayomi categories.
final class KavitaCategoryScopeTests: XCTestCase {
    let config = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
    var mock: MockTransport!

    override func setUp() {
        mock = MockTransport()
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"john","token":"jwt-1"}"#)
        mock.on("GET", "api/Library/libraries", body: #"[{"id":1,"name":"Manga"},{"id":3,"name":"Webtoons"},{"id":4,"name":"Comics"}]"#)
    }

    func client(_ scope: Set<String>?) -> KavitaClient {
        KavitaClient(config: config, apiKey: "KEY", categoryScope: scope, transport: mock)
    }

    func testCategoriesOnlyShowSelected() async throws {
        let all = try await client(nil).categories()
        XCTAssertEqual(all.map(\.id), ["1", "3", "4"])
        let some = try await client(["3", "4"]).categories()
        XCTAssertEqual(some.map(\.name), ["Webtoons", "Comics"])
    }

    func testNewlyAddedSendsLibraryFilter() async throws {
        mock.on("POST", "recently-added-v2", body: #"[{"id":8,"name":"New","libraryId":3},{"id":9,"name":"Stray","libraryId":2}]"#)
        let items = try await client(["4", "3"]).feed(.newlyAdded, limit: 10)
        XCTAssertEqual(items.map(\.title), ["New"], "anything the server lets through is still dropped")
        let statements = try XCTUnwrap(jsonBody(mock.lastRequest(containing: "recently-added-v2"))["statements"] as? [[String: Any]])
        XCTAssertEqual(statements.count, 1)
        XCTAssertEqual(statements[0]["field"] as? Int, 19)
        XCTAssertEqual(statements[0]["comparison"] as? Int, 5)
        XCTAssertEqual(statements[0]["value"] as? String, "3,4")
    }

    func testNewlyAddedUnscopedHasNoFilter() async throws {
        mock.on("POST", "recently-added-v2", body: #"[{"id":8,"name":"New","libraryId":3}]"#)
        _ = try await client(nil).feed(.newlyAdded, limit: 10)
        let statements = jsonBody(mock.lastRequest(containing: "recently-added-v2"))["statements"] as? [[String: Any]]
        XCTAssertEqual(statements?.count, 0)
    }

    func testOnDeckUsesLibraryIdForOneLibrary() async throws {
        mock.on("POST", "api/Series/on-deck", body: #"[{"id":9,"name":"OnDeck","libraryId":3}]"#)
        let items = try await client(["3"]).feed(.continueReading, limit: 5)
        XCTAssertEqual(items.map(\.title), ["OnDeck"])
        let url = try XCTUnwrap(mock.lastRequest(containing: "on-deck")?.url?.absoluteString)
        XCTAssertTrue(url.contains("libraryId=3"), url)
        XCTAssertTrue(url.contains("pageSize=5"), url)
    }

    func testOnDeckFiltersForSeveralLibraries() async throws {
        mock.on("POST", "api/Series/on-deck", body: #"[{"id":9,"name":"A","libraryId":3},{"id":10,"name":"B","libraryId":2},{"id":11,"name":"C","libraryId":1}]"#)
        let items = try await client(["1", "3"]).feed(.continueReading, limit: 5)
        XCTAssertEqual(items.map(\.title), ["A", "C"])
        let url = try XCTUnwrap(mock.lastRequest(containing: "on-deck")?.url?.absoluteString)
        XCTAssertTrue(url.contains("libraryId=0"), url)
        XCTAssertTrue(url.contains("pageSize=20"), url)
    }

    func testRecentlyUpdatedAndSearchFiltered() async throws {
        mock.on("POST", "recently-updated-series", body: """
        [{"seriesId":1,"seriesName":"Keep","libraryId":1},{"seriesId":2,"seriesName":"Drop","libraryId":4},{"seriesId":1,"seriesName":"Keep","libraryId":1}]
        """)
        mock.on("GET", "api/Search/search", body: #"{"series":[{"seriesId":5,"name":"Drop","libraryId":4},{"seriesId":6,"name":"Keep","libraryId":1}]}"#)
        let c = client(["1"])
        let updated = try await c.feed(.recentlyUpdated, limit: 10)
        XCTAssertEqual(updated.map(\.title), ["Keep"])
        let found = try await c.search("e")
        XCTAssertEqual(found.map(\.title), ["Keep"])
    }

    func testEmptyScopeMakesNoRequests() async throws {
        let c = client([])
        let feed = try await c.feed(.newlyAdded, limit: 10)
        let found = try await c.search("x")
        XCTAssertTrue(feed.isEmpty)
        XCTAssertTrue(found.isEmpty)
        XCTAssertNil(mock.lastRequest(containing: "api/Series"))
        XCTAssertNil(mock.lastRequest(containing: "api/Search"))
    }

    func testFactoryPassesScope() {
        let k = MangaServerFactory.make(config: config, credential: ServerCredential(apiKey: "K"), categoryScope: ["1"], transport: mock)
        XCTAssertEqual((k as? KavitaClient)?.categoryScope, ["1"])
        let s = MangaServerFactory.make(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://s")!),
                                        credential: nil, categoryScope: ["0"], transport: mock)
        XCTAssertEqual((s as? SuwayomiClient)?.categoryScope, ["0"])
    }
}

final class SuwayomiCategoryScopeTests: XCTestCase {
    let config = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local:4567")!)
    var mock: MockTransport!

    override func setUp() {
        mock = MockTransport()
    }

    func client(_ scope: Set<String>?) -> SuwayomiClient {
        SuwayomiClient(config: config, username: nil, password: nil, categoryScope: scope, transport: mock)
    }

    func query(_ containing: String) -> String {
        (jsonBody(mock.lastRequest(containing: containing))["query"] as? String) ?? ""
    }

    func testScopeFilter() {
        XCTAssertEqual(client(nil).scopeFilter, .all)
        XCTAssertEqual(client([]).scopeFilter, .nothing)
        XCTAssertEqual(client(["2", "1"]).scopeFilter, .filter("{categoryId: {in: [1, 2]}}"))
        XCTAssertEqual(client(["0"]).scopeFilter, .filter("{categoryId: {isNull: true}}"))
        XCTAssertEqual(client(["0", "5"]).scopeFilter,
                       .filter("{or: [{categoryId: {in: [5]}}, {categoryId: {isNull: true}}]}"))
    }

    func testCategoriesOnlyShowSelected() async throws {
        mock.onGraphQL("categories", body: #"{"data":{"categories":{"nodes":[{"id":0,"name":"Default","order":0},{"id":1,"name":"Webtoon","order":1},{"id":2,"name":"Reading","order":2}]}}}"#)
        let cats = try await client(["0", "2"]).categories()
        XCTAssertEqual(cats.map(\.name), ["Default", "Reading"])
    }

    func testSummariesCarryCategories() async throws {
        mock.onGraphQL("IN_LIBRARY_AT", body: """
        {"data":{"mangas":{"nodes":[
          {"id":1,"title":"Filed","categories":{"nodes":[{"id":2}]}},
          {"id":2,"title":"Loose","categories":{"nodes":[]}},
          {"id":3,"title":"Old Server"}
        ]}}}
        """)
        let items = try await client(nil).feed(.newlyAdded, limit: 5)
        XCTAssertEqual(items.map(\.categoryIDs), [["2"], ["0"], nil])
        XCTAssertFalse(query("IN_LIBRARY_AT").contains("filter:"))
    }

    func testNewlyAddedFiltersByCategory() async throws {
        mock.onGraphQL("IN_LIBRARY_AT", body: """
        {"data":{"mangas":{"nodes":[
          {"id":1,"title":"Filed","categories":{"nodes":[{"id":2}]}},
          {"id":1,"title":"Filed","categories":{"nodes":[{"id":2}]}},
          {"id":4,"title":"Elsewhere","categories":{"nodes":[{"id":7}]}}
        ]}}}
        """)
        let items = try await client(["2"]).feed(.newlyAdded, limit: 5)
        XCTAssertEqual(items.map(\.title), ["Filed"])
        XCTAssertTrue(query("IN_LIBRARY_AT").contains("filter: {categoryId: {in: [2]}}"), query("IN_LIBRARY_AT"))
    }

    func testSearchCombinesTitleAndCategory() async throws {
        mock.onGraphQL("includesInsensitive", body: #"{"data":{"mangas":{"nodes":[{"id":1,"title":"Hit","categories":{"nodes":[]}}]}}}"#)
        let found = try await client(["0"]).search("hi")
        XCTAssertEqual(found.map(\.title), ["Hit"])
        XCTAssertTrue(query("includesInsensitive").contains(
            "filter: {and: [{title: {includesInsensitive: $q}}, {categoryId: {isNull: true}}]}"), query("includesInsensitive"))
    }

    func testChapterFeedLimitsToMangaInSelectedCategories() async throws {
        mock.onGraphQL("{categoryId: {in: [3]}}) {", body: #"{"data":{"mangas":{"nodes":[{"id":5},{"id":7},{"id":5}]}}}"#)
        mock.onGraphQL("FETCHED_AT", body: """
        {"data":{"chapters":{"nodes":[
          {"lastReadAt":"0","manga":{"id":5,"title":"Five","categories":{"nodes":[{"id":3}]}}},
          {"lastReadAt":"0","manga":{"id":7,"title":"Seven","categories":{"nodes":[{"id":3}]}}}
        ]}}}
        """)
        let items = try await client(["3"]).feed(.recentlyUpdated, limit: 5)
        XCTAssertEqual(items.map(\.title), ["Five", "Seven"])
        XCTAssertTrue(query("{categoryId: {in: [3]}}) {").contains("{ nodes { id } }"))
        let chapters = mock.lastRequest(containing: "FETCHED_AT")
        XCTAssertTrue(query("FETCHED_AT").contains("mangaId: {in: $ids}"), query("FETCHED_AT"))
        let vars = jsonBody(chapters)["variables"] as? [String: Any]
        XCTAssertEqual(vars?["ids"] as? [Int], [5, 7])
    }

    func testUnscopedChapterFeedIsUnchanged() async throws {
        mock.onGraphQL("FETCHED_AT", body: #"{"data":{"chapters":{"nodes":[{"lastReadAt":"0","manga":{"id":5,"title":"Five"}}]}}}"#)
        _ = try await client(nil).feed(.recentlyUpdated, limit: 5)
        XCTAssertFalse(query("FETCHED_AT").contains("mangaId"))
        XCTAssertEqual(mock.requests.count, 1)
    }

    func testNothingSelectedMakesNoRequests() async throws {
        let c = client([])
        let a = try await c.feed(.newlyAdded, limit: 5)
        let b = try await c.feed(.continueReading, limit: 5)
        let d = try await c.search("x")
        XCTAssertTrue(a.isEmpty && b.isEmpty && d.isEmpty)
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testDetailSummaryHasCategories() async throws {
        mock.onGraphQL("manga(id", body: """
        {"data":{"manga":{"id":4,"title":"Frieren","thumbnailUrl":null,"categories":{"nodes":[{"id":1},{"id":2}]},"chapters":{"nodes":[]}}}}
        """)
        let d = try await client(nil).seriesDetail("4")
        XCTAssertEqual(d.summary.categoryIDs, ["1", "2"])
        XCTAssertTrue(query("manga(id").contains("categories { nodes { id } }"))
    }
}

final class SampleServerScopeTests: XCTestCase {
    func testDemoServerFollowsScope() async throws {
        let base = SampleLibraryServer(config: ServerConfig(kind: .kavita, name: "D", baseURL: URL(string: "https://demo.invalid")!),
                                       seriesCount: 12, latency: .zero)
        let server = base.scoped(to: ["short"])
        let cats = try await server.categories()
        XCTAssertEqual(cats.map(\.id), ["short"])
        let feed = try await server.feed(.recentlyUpdated, limit: 20)
        XCTAssertEqual(feed.map(\.ref.seriesID), ["12", "9", "6", "3"])
        let all = try await base.feed(.recentlyUpdated, limit: 20)
        XCTAssertEqual(all.count, 12)
        // Progress is shared between copies.
        let chapter = Chapter(id: "6-1", seriesRef: SeriesRef(serverID: base.config.id, seriesID: "6"), title: "1",
                              number: 1, pageCount: 20)
        try await base.saveProgress(chapter: chapter, libraryID: nil, page: 3, completed: false)
        let reading = try await server.feed(.continueReading, limit: 5)
        XCTAssertEqual(reading.map(\.ref.seriesID), ["6"])
    }
}
