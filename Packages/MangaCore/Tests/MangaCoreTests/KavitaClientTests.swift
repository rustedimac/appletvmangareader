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

    func testCategoriesSendTheKeyHeaderWithoutLoggingIn() async throws {
        mock.on("GET", "api/Library/libraries", body: #"[{"id":1,"name":"Manga Library","type":0},{"id":3,"name":"Webtoons","type":0}]"#)
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.name), ["Manga Library", "Webtoons"])
        XCTAssertEqual(cats.map(\.id), ["1", "3"])
        let req = try XCTUnwrap(mock.lastRequest(containing: "libraries"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "KEY")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        // No login, so the user's refresh token (and browser session) is left alone.
        XCTAssertNil(mock.lastRequest(containing: "authenticate"))
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

    func testSaveProgressNeedsOnlyTheChapter() async throws {
        // Continue Reading items and some feeds don't carry the library or
        // volume; Kavita fills them in from the chapter.
        mock.on("POST", "api/Reader/progress", body: "")
        let ref = SeriesRef(serverID: config.id, seriesID: "5")
        let chapter = Chapter(id: "77", seriesRef: ref, title: "1", number: 1, pageCount: 20)
        try await client.saveProgress(chapter: chapter, libraryID: nil, page: 6, completed: false)
        let body = jsonBody(mock.lastRequest(containing: "api/Reader/progress"))
        XCTAssertEqual(body["chapterId"] as? Int, 77)
        XCTAssertEqual(body["pageNum"] as? Int, 6)
        XCTAssertEqual(body["volumeId"] as? Int, 0)
        XCTAssertEqual(body["libraryId"] as? Int, 0)
    }

    func testChapterLastReadDate() throws {
        let ref = SeriesRef(serverID: config.id, seriesID: "5")
        let json = """
        [{"id":1,"minNumber":1,"name":"1","chapters":[
          {"id":10,"range":"1","minNumber":1,"sortOrder":1,"pages":20,"pagesRead":7,"volumeId":1,"lastReadingProgressUtc":"2026-11-20T10:00:00.1234567"},
          {"id":11,"range":"2","minNumber":2,"sortOrder":2,"pages":20,"pagesRead":0,"volumeId":1,"lastReadingProgressUtc":"0001-01-01T00:00:00"}
        ]}]
        """
        let volumes = try HTTPClient.decode([KavitaVolumeDTO].self, from: Data(json.utf8))
        let chapters = KavitaClient.chapters(from: volumes, seriesRef: ref)
        let expected = try XCTUnwrap(DateParsing.parse("2026-11-20T10:00:00.1234567"))
        XCTAssertEqual(try XCTUnwrap(chapters[0].lastReadAt).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(chapters[1].lastReadAt, "0001-01-01 means never read")
    }

    // MARK: Sign-in with username and password

    func testSignInReusesTheAppsKey() async throws {
        let m = MockTransport()
        m.on("POST", "api/Account/login", body: """
        {"username":"John","token":"jwt","refreshToken":"r","apiKey":"OPDS","authKeys":[
          {"id":1,"key":"OPDS","name":"opds","expiresAtUtc":"2026-12-25T00:00:00Z"},
          {"id":2,"key":"APPKEY","name":"Apple TV Manga Reader","expiresAtUtc":null}]}
        """)
        let credential = try await KavitaClient.signIn(baseURL: config.baseURL, username: " john ", password: "pw", transport: m)
        XCTAssertEqual(credential, ServerCredential(apiKey: "APPKEY", username: "John"))
        XCTAssertNil(credential.password, "the password is never kept")
        let login = jsonBody(m.lastRequest(containing: "api/Account/login"))
        XCTAssertEqual(login["username"] as? String, "john")
        XCTAssertEqual(login["password"] as? String, "pw")
        XCTAssertNil(m.lastRequest(containing: "create-auth-key"))
    }

    func testSignInCreatesANonExpiringKey() async throws {
        let m = MockTransport()
        m.on("POST", "api/Account/login", body: #"{"username":"kid","token":"jwt","apiKey":"OPDS","authKeys":[{"key":"OPDS","name":"opds"}]}"#)
        m.on("POST", "api/Account/create-auth-key", body: #"{"id":3,"key":"NEWKEY","name":"Apple TV Manga Reader","createdAtUtc":"2026-11-25T00:00:00Z"}"#)
        let credential = try await KavitaClient.signIn(baseURL: config.baseURL, username: "kid", password: "pw", transport: m)
        XCTAssertEqual(credential.apiKey, "NEWKEY")
        let create = try XCTUnwrap(m.lastRequest(containing: "create-auth-key"))
        XCTAssertEqual(create.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        let body = jsonBody(create)
        XCTAssertEqual(body["name"] as? String, KavitaClient.authKeyName)
        XCTAssertEqual(body["keyLength"] as? Int, 32)
        XCTAssertNil(body["expiresUtc"], "no expiry")
    }

    func testSignInReplacesAnExpiredAppKey() async throws {
        let m = MockTransport()
        m.on("POST", "api/Account/login", body: #"{"username":"kid","token":"jwt","apiKey":"OPDS","authKeys":[{"key":"OLD","name":"Apple TV Manga Reader","expiresAtUtc":"2020-01-01T00:00:00Z"}]}"#)
        m.on("POST", "api/Account/create-auth-key", body: #"{"key":"FRESH","name":"Apple TV Manga Reader"}"#)
        let credential = try await KavitaClient.signIn(baseURL: config.baseURL, username: "kid", password: "pw", transport: m)
        XCTAssertEqual(credential.apiKey, "FRESH")
    }

    func testSignInFallsBackToTheOPDSKey() async throws {
        // Read-only users may not create keys; older servers have no auth keys.
        let m = MockTransport()
        m.on("POST", "api/Account/login", body: #"{"username":"guest","token":"jwt","apiKey":"OPDS"}"#)
        m.on("POST", "api/Account/create-auth-key", status: 403, body: "")
        let credential = try await KavitaClient.signIn(baseURL: config.baseURL, username: "guest", password: "pw", transport: m)
        XCTAssertEqual(credential, ServerCredential(apiKey: "OPDS", username: "guest"))
    }

    func testSignInWithWrongPassword() async {
        let m = MockTransport()
        m.on("POST", "api/Account/login", status: 401, body: "Your credentials are not correct")
        do {
            _ = try await KavitaClient.signIn(baseURL: config.baseURL, username: "john", password: "bad", transport: m)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
    }

    func testUsernameOfAPastedKey() async throws {
        let name = try await client.username()
        XCTAssertEqual(name, "john")
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

    func testOlderServerFallsBackToJWT() async throws {
        // The key header is turned down once; the client switches to a JWT.
        let flaky = FlakyTransport(inner: mock)
        mock.on("GET", "api/Library/libraries", body: #"[{"id":1,"name":"L"}]"#)
        let c = KavitaClient(config: config, apiKey: "KEY", transport: flaky)
        let cats = try await c.categories()
        XCTAssertEqual(cats.count, 1)
        XCTAssertEqual(flaky.authCalls, 1)
        XCTAssertEqual(mock.lastRequest(containing: "libraries")?.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
        // Later calls keep using the JWT, without logging in again.
        _ = try await c.categories()
        XCTAssertEqual(flaky.authCalls, 1)
    }

    func testReloginAfterExpiredJWT() async throws {
        let script = ScriptedKavitaTransport(inner: mock)
        mock.on("GET", "api/Library/libraries", body: #"[{"id":1,"name":"L"}]"#)
        let c = KavitaClient(config: config, apiKey: "KEY", transport: script)
        _ = try await c.categories()           // header refused → JWT 1
        script.expireNextBearer = true
        _ = try await c.categories()           // JWT expired → login again
        XCTAssertEqual(script.authCalls, 2)
    }

    func testWrongKeyFailsWithoutLooping() async {
        let refusing = MockTransport()
        refusing.on("POST", "api/Plugin/authenticate", status: 401, body: "")
        refusing.on("GET", "api/Library/libraries", status: 401, body: "")
        let c = KavitaClient(config: config, apiKey: "WRONG", transport: refusing)
        do {
            _ = try await c.categories()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
        XCTAssertEqual(refusing.requests.count, 2)
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

/// Refuses the `x-api-key` header like Kavita before auth keys, and can
/// expire the next Bearer token.
final class ScriptedKavitaTransport: HTTPTransport, @unchecked Sendable {
    let inner: MockTransport
    private let lock = NSLock()
    private(set) var authCalls = 0
    var expireNextBearer = false

    init(inner: MockTransport) { self.inner = inner }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!.absoluteString
        let refuse: Bool = lock.withLock {
            if url.contains("authenticate") { authCalls += 1; return false }
            if request.value(forHTTPHeaderField: "x-api-key") != nil { return true }
            if expireNextBearer, request.value(forHTTPHeaderField: "Authorization") != nil {
                expireNextBearer = false
                return true
            }
            return false
        }
        if refuse {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        return try await inner.send(request)
    }
}
