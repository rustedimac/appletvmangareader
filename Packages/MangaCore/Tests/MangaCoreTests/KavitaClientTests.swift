import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class KavitaClientTests: XCTestCase {
    let config = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
    var mock: MockTransport!
    var client: KavitaClient!

    override func setUp() {
        mock = MockTransport()
        mock.on("POST", "api/Plugin/authenticate", body: fixture("kavita-authenticate"))
        client = KavitaClient(config: config, apiKey: " KEY ", transport: mock)
    }

    func testValidateLogsInWithApiKey() async throws {
        let message = try await client.validate()
        XCTAssertEqual(message, "Signed in to Kavita as john")
        let url = try XCTUnwrap(mock.lastRequest(containing: "authenticate")?.url?.absoluteString)
        XCTAssertTrue(url.contains("apiKey=KEY"), url)
        XCTAssertTrue(url.contains("pluginName=AppleTVMangaReader"), url)
    }

    func testMissingKeyThrows() async {
        let c = KavitaClient(config: config, apiKey: "", transport: mock)
        do {
            _ = try await c.categories()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MangaError, .missingCredential)
        }
    }

    func testCategoriesUseBearerToken() async throws {
        mock.on("GET", "api/Library/libraries", body: fixture("kavita-libraries"))
        mock.on("GET", "api/Collection", body: "[]")
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.name), ["Manga Library", "Webtoons"])
        XCTAssertEqual(cats.map(\.id), ["1", "3"])
        XCTAssertEqual(cats.map(\.kind), [.library, .library])
        let req = try XCTUnwrap(mock.lastRequest(containing: "libraries"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
    }

    func testSeriesInLibrarySendsFilter() async throws {
        mock.on("POST", "api/Series/v2", body: fixture("kavita-series-v2-page1"),
                headers: ["Pagination": #"{"currentPage":1,"itemsPerPage":2,"totalItems":179,"totalPages":90}"#])
        let page = try await client.series(in: MangaCategory(id: "1", name: "Manga"), page: 1, pageSize: 2)
        XCTAssertEqual(page.items.map(\.title), ["A Ninja and an Assassin Under One Roof", "A Witch's Life in Mongol"])
        XCTAssertEqual(page.items.map(\.unreadCount), [1383, 1031])
        XCTAssertEqual(page.items.first?.libraryID, "1")
        XCTAssertTrue(page.hasMore)
        let cover = try XCTUnwrap(page.items.first?.coverURL?.absoluteString)
        XCTAssertEqual(cover, "http://kavita.local:5000/api/Image/series-cover?apiKey=KEY&seriesId=29")

        let req = mock.lastRequest(containing: "api/Series/v2")
        let url = try XCTUnwrap(req?.url?.absoluteString)
        XCTAssertTrue(url.contains("libraryId=1") && url.contains("pageNumber=1") && url.contains("pageSize=2"), url)
        let body = jsonBody(req)
        let statements = try XCTUnwrap(body["statements"] as? [[String: Any]])
        XCTAssertEqual(statements.first?["field"] as? Int, 19)
        XCTAssertEqual(statements.first?["comparison"] as? Int, 0)
        XCTAssertEqual(statements.first?["value"] as? String, "1")
        XCTAssertEqual(body["combination"] as? Int, 1)
    }

    func testPaginationHeaderEndsPaging() async throws {
        // A full page that is also the last one: only the header can tell.
        mock.on("POST", "api/Series/v2", body: fixture("kavita-series-v2-page1"),
                headers: ["Pagination": #"{"currentPage":90,"itemsPerPage":2,"totalItems":180,"totalPages":90}"#])
        let page = try await client.series(in: MangaCategory(id: "1", name: "Manga"), page: 90, pageSize: 2)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertFalse(page.hasMore)
    }

    func testPagingFallsBackToCountWithoutHeader() async throws {
        mock.on("POST", "api/Series/v2", body: fixture("kavita-series-v2-last"))
        let page = try await client.series(in: MangaCategory(id: "1", name: "Manga"), page: 2, pageSize: 2)
        XCTAssertEqual(page.items.map(\.title), ["A-Channel"])
        XCTAssertFalse(page.hasMore)
    }

    func testPaginationHeaderParsing() {
        func response(_ value: String?) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "http://h")!, statusCode: 200, httpVersion: nil,
                            headerFields: value.map { ["Pagination": $0] })!
        }
        let parsed = KavitaPaginationHeader.parse(response(#"{"currentPage":1,"itemsPerPage":2,"totalItems":179,"totalPages":90}"#))
        XCTAssertEqual(parsed, KavitaPaginationHeader(currentPage: 1, itemsPerPage: 2, totalItems: 179, totalPages: 90))
        XCTAssertEqual(parsed?.hasMore, true)
        // Empty on-deck result from the live server.
        XCTAssertEqual(KavitaPaginationHeader.parse(response(#"{"currentPage":1,"itemsPerPage":2,"totalItems":0,"totalPages":0}"#))?.hasMore, false)
        XCTAssertNil(KavitaPaginationHeader.parse(response(nil)))
        XCTAssertNil(KavitaPaginationHeader.parse(response("garbage")))
    }

    func testCollectionsAreListedAfterLibraries() async throws {
        mock.on("GET", "api/Library/libraries", body: fixture("kavita-libraries"))
        mock.on("GET", "api/Collection", body: fixture("kavita-collections"))
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.name), ["Manga Library", "Webtoons", "Summer Picks"]) // empty one hidden
        XCTAssertEqual(cats.last?.kind, .collection)
        XCTAssertEqual(cats.last?.id, "collection-4")
        XCTAssertEqual(Set(cats.map(\.id)).count, cats.count)

        mock.on("POST", "api/Series/v2", body: fixture("kavita-series-v2-last"),
                headers: ["Pagination": #"{"currentPage":1,"itemsPerPage":20,"totalItems":1,"totalPages":1}"#])
        let page = try await client.series(in: try XCTUnwrap(cats.last), page: 1, pageSize: 20)
        XCTAssertEqual(page.items.map(\.title), ["A-Channel"])
        XCTAssertFalse(page.hasMore)
        let req = mock.lastRequest(containing: "api/Series/v2")
        XCTAssertFalse(req?.url?.absoluteString.contains("libraryId") ?? true)
        let statements = try XCTUnwrap(jsonBody(req)["statements"] as? [[String: Any]])
        XCTAssertEqual(statements.first?["field"] as? Int, 7)
        XCTAssertEqual(statements.first?["value"] as? String, "4")
    }

    func testCollectionsFailureDoesNotHideLibraries() async throws {
        mock.on("GET", "api/Library/libraries", body: fixture("kavita-libraries"))
        mock.on("GET", "api/Collection", status: 500, body: "boom")
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.id), ["1", "3"])
    }

    func testRecentlyUpdatedDedupesSeries() async throws {
        mock.on("POST", "recently-updated-series", body: fixture("kavita-recently-updated"))
        let items = try await client.feed(.recentlyUpdated, limit: 10)
        XCTAssertEqual(items.map(\.ref.seriesID), ["157", "2", "65"])
        XCTAssertEqual(items.first?.title, "Let's Go, Kaikigumi")
        XCTAssertEqual(items.first?.libraryID, "1")
        let limited = try await client.feed(.recentlyUpdated, limit: 2)
        XCTAssertEqual(limited.count, 2)
    }

    func testFeedEndpoints() async throws {
        mock.on("POST", "api/Series/on-deck", body: #"[{"id":9,"name":"OnDeck"}]"#)
        mock.on("POST", "recently-added-v2", body: #"[{"id":8,"name":"New"}]"#)
        let deck = try await client.feed(.continueReading, limit: 5)
        let added = try await client.feed(.newlyAdded, limit: 5)
        XCTAssertEqual(deck.map(\.title), ["OnDeck"])
        XCTAssertEqual(added.map(\.title), ["New"])
        XCTAssertTrue(mock.lastRequest(containing: "on-deck")?.url?.absoluteString.contains("libraryId=0") ?? false)
    }

    func testSeriesDetailOrdersVolumesAndChapters() async throws {
        mock.on("GET", "api/Series/5", body: #"{"id":5,"name":"Berserk","libraryId":1}"#)
        mock.on("GET", "api/Series/metadata", body: #"{"summary":"Guts.","genres":[{"title":"Dark Fantasy"}],"writers":[{"name":"Kentaro Miura"}],"publicationStatus":0}"#)
        mock.on("GET", "api/Series/volumes", body: """
        [
          {"id":30,"minNumber":100000,"name":"Specials","chapters":[{"id":300,"range":"Art Book","minNumber":100000,"sortOrder":1,"pages":40,"pagesRead":0,"isSpecial":true,"title":"Art Book","volumeId":30}]},
          {"id":20,"minNumber":-100000,"name":"-100000","chapters":[
            {"id":202,"range":"12","minNumber":12,"sortOrder":12,"pages":20,"pagesRead":5,"volumeId":20},
            {"id":201,"range":"11","minNumber":11,"sortOrder":11,"pages":20,"pagesRead":20,"volumeId":20,"titleName":"The Black Swordsman"}
          ]},
          {"id":10,"minNumber":1,"name":"1","chapters":[{"id":100,"range":"-100000","minNumber":-100000,"sortOrder":-100000,"pages":180,"pagesRead":180,"volumeId":10}]}
        ]
        """)
        let detail = try await client.seriesDetail("5")
        XCTAssertEqual(detail.chapters.map(\.id), ["100", "201", "202", "300"])
        XCTAssertEqual(detail.chapters.map(\.title), ["Volume 1", "Chapter 11: The Black Swordsman", "Chapter 12", "Art Book"])
        XCTAssertEqual(detail.chapters.map(\.isRead), [true, true, false, false])
        XCTAssertEqual(detail.chapters[2].lastPageRead, 5)
        XCTAssertEqual(detail.chapters[2].volumeID, "20")
        XCTAssertEqual(detail.continueChapter?.id, "202")
        XCTAssertEqual(detail.authors, ["Kentaro Miura"])
        XCTAssertEqual(detail.genres, ["Dark Fantasy"])
        XCTAssertEqual(detail.status, "Ongoing")
        XCTAssertEqual(detail.synopsis, "Guts.")
    }

    func testPagesUseFileDimensions() async throws {
        mock.on("GET", "file-dimensions", body: """
        [{"width":800,"height":1200,"pageNumber":0,"fileName":"001.jpg","isWide":false},
         {"width":1600,"height":1200,"pageNumber":1,"fileName":"002.jpg","isWide":true}]
        """)
        let ref = SeriesRef(serverID: config.id, seriesID: "5")
        let chapter = Chapter(id: "77", seriesRef: ref, volumeID: "3", title: "1", number: 1, pageCount: 3)
        let pages = try await client.pages(for: chapter)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[1].size, PageSize(width: 1600, height: 1200))
        XCTAssertTrue(pages[1].size?.isWide ?? false)
        XCTAssertNil(pages[2].size)
        XCTAssertEqual(pages[0].url.absoluteString,
                       "http://kavita.local:5000/api/Reader/image?apiKey=KEY&chapterId=77&extractPdf=true&page=0")
    }

    func testRealVolumesSortChaptersAndKeepTitles() async throws {
        mock.on("GET", "api/Series/29", body: #"{"id":29,"name":"A Ninja and an Assassin Under One Roof","localizedName":"","pages":1383,"pagesRead":0,"libraryId":1,"latestReadDate":"0001-01-01T00:00:00"}"#)
        mock.on("GET", "api/Series/metadata", status: 404, body: "")
        mock.on("GET", "api/Series/volumes", body: fixture("kavita-volumes"))
        let detail = try await client.seriesDetail("29")
        // Volume 1 first, then loose chapters sorted by sortOrder (the server
        // sends them as 50, 51, 51.5 but not always in that order).
        XCTAssertEqual(detail.chapters.map(\.id), ["2400", "2401", "2402", "2388", "2390", "2389"])
        XCTAssertEqual(detail.chapters.map(\.title),
                       ["Vol.1 Ch.1", "Vol.1 Ch.2", "Vol.1 Ch.3", "Ch.50", "Ch.51", "Ch.51.5 - Ninkoro 4koma - KILLER ROBOT"])
        XCTAssertEqual(detail.chapters.map(\.volumeID), ["109", "109", "109", "108", "108", "108"])
        XCTAssertEqual(detail.chapters[0].isRead, true)
        XCTAssertEqual(detail.chapters[1].lastPageRead, 4)
        XCTAssertEqual(detail.continueChapter?.id, "2401")
        XCTAssertNil(detail.synopsis) // metadata failure is tolerated
    }

    func testRealFileDimensionsMarkSpreads() async throws {
        mock.on("GET", "file-dimensions", body: fixture("kavita-file-dimensions"))
        let ref = SeriesRef(serverID: config.id, seriesID: "29")
        let chapter = Chapter(id: "2437", seriesRef: ref, volumeID: "113", title: "Vol.5 Ch.34", number: 1, pageCount: 28)
        let pages = try await client.pages(for: chapter)
        XCTAssertEqual(pages.count, 28)
        XCTAssertEqual(pages.filter { $0.size?.isWide == true }.map(\.index), [6, 7])
        XCTAssertTrue(pages.allSatisfy { $0.size?.wideOverride == nil })
        let layout = SpreadLayout(sizes: pages.map(\.size), firstPageAlone: true, shift: false)
        XCTAssertTrue(layout.spreads.contains(.single(6)))
        XCTAssertTrue(layout.spreads.contains(.single(7)))
    }

    func testKavitaWideFlagOverridesAspectRatio() {
        let flagged = KavitaClient.pageSize(KavitaFileDimensionDTO(width: 1000, height: 1000, pageNumber: 0, isWide: true))
        XCTAssertEqual(flagged.wideOverride, true)
        XCTAssertTrue(flagged.isWide)
        let notWide = KavitaClient.pageSize(KavitaFileDimensionDTO(width: 2000, height: 1000, pageNumber: 1, isWide: false))
        XCTAssertFalse(notWide.isWide)
        let agrees = KavitaClient.pageSize(KavitaFileDimensionDTO(width: 2672, height: 1920, pageNumber: 6, isWide: true))
        XCTAssertNil(agrees.wideOverride)
        XCTAssertTrue(agrees.isWide)
        let missing = KavitaClient.pageSize(KavitaFileDimensionDTO(width: 800, height: 1200, pageNumber: 2, isWide: nil))
        XCTAssertNil(missing.wideOverride)
        XCTAssertFalse(missing.isWide)
    }

    func testSaveProgressBody() async throws {
        mock.on("POST", "api/Reader/progress", body: "")
        let ref = SeriesRef(serverID: config.id, seriesID: "5")
        let chapter = Chapter(id: "77", seriesRef: ref, volumeID: "3", title: "1", number: 1, pageCount: 20)
        try await client.saveProgress(chapter: chapter, libraryID: "1", page: 4, completed: false)
        var body = jsonBody(mock.lastRequest(containing: "api/Reader/progress"))
        XCTAssertEqual(body["pageNum"] as? Int, 4)
        XCTAssertEqual(body["chapterId"] as? Int, 77)
        XCTAssertEqual(body["volumeId"] as? Int, 3)
        XCTAssertEqual(body["seriesId"] as? Int, 5)
        XCTAssertEqual(body["libraryId"] as? Int, 1)
        try await client.saveProgress(chapter: chapter, libraryID: "1", page: 19, completed: true)
        body = jsonBody(mock.lastRequest(containing: "api/Reader/progress"))
        XCTAssertEqual(body["pageNum"] as? Int, 20)
    }

    func testReloginAfterExpiredToken() async throws {
        // First libraries call returns 401, the retry succeeds.
        let flaky = FlakyTransport(inner: mock)
        mock.on("GET", "api/Library/libraries", body: #"[{"id":1,"name":"L"}]"#)
        mock.on("GET", "api/Collection", body: "[]")
        let c = KavitaClient(config: config, apiKey: "KEY", transport: flaky)
        let cats = try await c.categories()
        XCTAssertEqual(cats.count, 1)
        XCTAssertEqual(flaky.authCalls, 2)
    }

    func testBasePathPrefixIsKept() throws {
        let c = KavitaClient(config: ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "https://example.com/kavita/")!),
                             apiKey: "K", transport: mock)
        XCTAssertEqual(c.coverURL(seriesID: 1)?.absoluteString, "https://example.com/kavita/api/Image/series-cover?apiKey=K&seriesId=1")
    }

    func testOPDSParsing() {
        let parsed = KavitaOPDS.parse("http://kavita.home/api/opds/AbC123")
        XCTAssertEqual(parsed?.baseURL.absoluteString, "http://kavita.home")
        XCTAssertEqual(parsed?.apiKey, "AbC123")

        let prefixed = KavitaOPDS.parse(" https://host.example:8443/kavita/api/opds/abcdef-123/ ")
        XCTAssertEqual(prefixed?.baseURL.absoluteString, "https://host.example:8443/kavita")
        XCTAssertEqual(prefixed?.apiKey, "abcdef-123")

        XCTAssertNil(KavitaOPDS.parse("http://kavita.home/"))
        XCTAssertNil(KavitaOPDS.parse("http://kavita.home/api/opds"))
        XCTAssertNil(KavitaOPDS.parse("not a url"))
    }
}

/// Fails the first authenticated request with 401 to exercise re-login.
final class FlakyTransport: HTTPTransport, @unchecked Sendable {
    let inner: MockTransport
    private var failed = false
    private(set) var authCalls = 0
    private let lock = NSLock()

    init(inner: MockTransport) { self.inner = inner }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!.absoluteString
        lock.lock()
        if url.contains("authenticate") { authCalls += 1 }
        let shouldFail = !failed && !url.contains("authenticate")
        if shouldFail { failed = true }
        lock.unlock()
        if shouldFail {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        return try await inner.send(request)
    }
}
