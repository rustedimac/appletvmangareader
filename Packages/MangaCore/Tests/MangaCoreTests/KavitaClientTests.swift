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
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"john","token":"jwt-1","refreshToken":"r","apiKey":"KEY"}"#)
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
        mock.on("GET", "api/Library/libraries", body: #"[{"id":1,"name":"Manga Library","type":0},{"id":3,"name":"Webtoons","type":0}]"#)
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.name), ["Manga Library", "Webtoons"])
        XCTAssertEqual(cats.map(\.id), ["1", "3"])
        let req = try XCTUnwrap(mock.lastRequest(containing: "libraries"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
    }

    func testSeriesInLibrarySendsFilter() async throws {
        mock.on("POST", "api/Series/v2", body: #"[{"id":5,"name":"Vinland Saga","localizedName":"","pages":200,"pagesRead":50,"libraryId":1,"created":"2024-05-01T12:34:56.1234567"}]"#)
        let page = try await client.series(in: MangaCategory(id: "1", name: "Manga"), page: 1, pageSize: 1)
        XCTAssertEqual(page.items.first?.title, "Vinland Saga")
        XCTAssertEqual(page.items.first?.unreadCount, 150)
        XCTAssertEqual(page.items.first?.libraryID, "1")
        XCTAssertTrue(page.hasMore)
        let cover = try XCTUnwrap(page.items.first?.coverURL?.absoluteString)
        XCTAssertEqual(cover, "http://kavita.local:5000/api/Image/series-cover?apiKey=KEY&seriesId=5")

        let req = mock.lastRequest(containing: "api/Series/v2")
        let body = jsonBody(req)
        let statements = try XCTUnwrap(body["statements"] as? [[String: Any]])
        XCTAssertEqual(statements.first?["field"] as? Int, 19)
        XCTAssertEqual(statements.first?["comparison"] as? Int, 0)
        XCTAssertEqual(statements.first?["value"] as? String, "1")
        XCTAssertEqual(body["combination"] as? Int, 1)
    }

    func testRecentlyUpdatedDedupesSeries() async throws {
        mock.on("POST", "recently-updated-series", body: """
        [{"seriesId":1,"seriesName":"A","libraryId":1},{"seriesId":1,"seriesName":"A","libraryId":1},{"seriesId":2,"seriesName":"B","libraryId":1}]
        """)
        let items = try await client.feed(.recentlyUpdated, limit: 10)
        XCTAssertEqual(items.map(\.title), ["A", "B"])
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
