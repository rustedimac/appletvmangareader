import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Fixtures were recorded from a real Komga 1.30.2 loaded with code-drawn
/// test pages; titles and people are invented.
final class KomgaClientTests: XCTestCase {
    let config = ServerConfig(kind: .komga, name: "Komga", baseURL: URL(string: "http://komga.local:25600")!)
    let manga = "0SB719FAHCE3H"
    let comics = "0SB719FX9C0FF"
    let seriesID = "0SB719FFDC3VJ"
    let bookID = "0SB719FFDC3VK"
    var mock: MockTransport!

    override func setUp() {
        mock = MockTransport()
    }

    func client(apiKey: String? = "KEY", username: String? = nil, password: String? = nil,
                scope: Set<String>? = nil) -> KomgaClient {
        KomgaClient(config: config, apiKey: apiKey, username: username, password: password,
                    categoryScope: scope, transport: mock)
    }

    // MARK: Auth

    func testValidateWithAPIKey() async throws {
        mock.on("GET", "api/v2/users/me", body: loadFixture("komga-user-me"))
        mock.on("GET", "actuator/info", body: loadFixture("komga-actuator-info"))
        let message = try await client(apiKey: " KEY ").validate()
        XCTAssertEqual(message, "Signed in to Komga 1.30.2 as admin@example.org")
        let request = try XCTUnwrap(mock.lastRequest(containing: "users/me"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "KEY")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testValidateWithEmailAndPasswordUsesBasicAuth() async throws {
        mock.on("GET", "api/v2/users/me", body: loadFixture("komga-user-me"))
        _ = try await client(apiKey: nil, username: "reader@example.org", password: "secret").validate()
        let request = try XCTUnwrap(mock.lastRequest(containing: "users/me"))
        let expected = "Basic " + Data("reader@example.org:secret".utf8).base64EncodedString()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expected)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
    }

    func testValidateStillWorksWithoutActuator() async throws {
        mock.on("GET", "api/v2/users/me", body: loadFixture("komga-user-me"))
        let message = try await client().validate()
        XCTAssertEqual(message, "Signed in to Komga as admin@example.org")
    }

    func testWrongLoginIsUnauthorized() async {
        mock.on("GET", "api/v2/users/me", status: 401, body: loadFixture("komga-unauthorized"))
        do {
            _ = try await client().validate()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
    }

    func testNoLoginIsMissingCredential() async {
        do {
            _ = try await client(apiKey: nil).validate()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MangaError, .missingCredential)
        }
    }

    func testImagesGetTheLoginOnlyForThisServer() {
        let c = client()
        let page = c.authorize(URLRequest(url: URL(string: "http://komga.local:25600/api/v1/books/x/pages/1")!))
        XCTAssertEqual(page.value(forHTTPHeaderField: "X-API-Key"), "KEY")
        let other = c.authorize(URLRequest(url: URL(string: "http://elsewhere.example/cover.jpg")!))
        XCTAssertNil(other.value(forHTTPHeaderField: "X-API-Key"))
    }

    // MARK: Libraries and series

    func testCategoriesAreLibrariesSortedByName() async throws {
        mock.on("GET", "api/v1/libraries", body: loadFixture("komga-libraries"))
        let all = try await client().categories()
        XCTAssertEqual(all.map(\.name), ["Comics", "Manga"])
        XCTAssertEqual(all.map(\.id), [comics, manga])
        let scoped = try await client(scope: [manga]).categories()
        XCTAssertEqual(scoped.map(\.name), ["Manga"])
    }

    func testSeriesInLibraryPostsSearchAndPagesFromZero() async throws {
        mock.on("POST", "api/v1/series/list", body: loadFixture("komga-series-list"))
        let page = try await client().series(in: MangaCategory(id: manga, name: "Manga"), page: 1, pageSize: 20)
        XCTAssertEqual(page.items.map(\.title), ["Lantern Courier", "Paper Moon Post"])
        XCTAssertFalse(page.hasMore, "Komga said last: true")
        let first = try XCTUnwrap(page.items.first)
        XCTAssertEqual(first.ref, SeriesRef(serverID: config.id, seriesID: seriesID))
        XCTAssertEqual(first.libraryID, manga)
        XCTAssertEqual(first.unreadCount, 1)
        XCTAssertEqual(first.coverURL?.absoluteString, "http://komga.local:25600/api/v1/series/\(seriesID)/thumbnail")
        XCTAssertEqual(first.chapterCount, 2, "Komga counts books")
        XCTAssertEqual(first.countUnit, .book)
        XCTAssertEqual(PosterBadges(series: first).caption, "2 books")

        let request = try XCTUnwrap(mock.lastRequest(containing: "series/list"))
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("page=0"), url)
        XCTAssertTrue(url.contains("size=20"), url)
        XCTAssertTrue(url.contains("sort=metadata.titleSort%2Casc"), url)
        let condition = try XCTUnwrap(jsonBody(request)["condition"] as? [String: Any])
        let library = try XCTUnwrap(condition["libraryId"] as? [String: Any])
        XCTAssertEqual(library["operator"] as? String, "is")
        XCTAssertEqual(library["value"] as? String, manga)
    }

    func testSecondPageAsksForPageOne() async throws {
        mock.on("POST", "api/v1/series/list", body: loadFixture("komga-series-list"))
        _ = try await client().series(in: MangaCategory(id: manga, name: "Manga"), page: 3, pageSize: 20)
        XCTAssertTrue(mock.lastRequest(containing: "series/list")?.url?.absoluteString.contains("page=2") ?? false)
    }

    // MARK: Feeds and search

    func testContinueReadingIsBooksInProgressGroupedBySeries() async throws {
        mock.on("POST", "api/v1/books/list", body: loadFixture("komga-books-in-progress"))
        let items = try await client().feed(.continueReading, limit: 10)
        XCTAssertEqual(items.map(\.title), ["Lantern Courier"])
        XCTAssertEqual(items.first?.ref.seriesID, seriesID)

        let request = try XCTUnwrap(mock.lastRequest(containing: "books/list"))
        XCTAssertTrue(request.url?.absoluteString.contains("sort=readProgress.readDate%2Cdesc") ?? false)
        let condition = try XCTUnwrap(jsonBody(request)["condition"] as? [String: Any])
        let status = try XCTUnwrap(condition["readStatus"] as? [String: Any])
        XCTAssertEqual(status["value"] as? String, "IN_PROGRESS")
    }

    func testContinueReadingInScopedLibrariesCombinesConditions() async throws {
        mock.on("POST", "api/v1/books/list", body: loadFixture("komga-books-in-progress"))
        _ = try await client(scope: [manga, comics]).feed(.continueReading, limit: 10)
        let body = jsonBody(mock.lastRequest(containing: "books/list"))
        let all = try XCTUnwrap((body["condition"] as? [String: Any])?["allOf"] as? [[String: Any]])
        XCTAssertEqual(all.count, 2)
        let any = try XCTUnwrap(all[1]["anyOf"] as? [[String: Any]])
        let ids = any.compactMap { ($0["libraryId"] as? [String: Any])?["value"] as? String }
        XCTAssertEqual(ids, [manga, comics], "sorted by id")
    }

    func testNewlyAddedAndUpdatedPassLibraries() async throws {
        mock.on("GET", "api/v1/series/new", body: loadFixture("komga-series-new"))
        mock.on("GET", "api/v1/series/updated", body: loadFixture("komga-series-updated"))
        let added = try await client(scope: [manga]).feed(.newlyAdded, limit: 10)
        // Harbor Lights is in Comics, so the client drops it too.
        XCTAssertEqual(added.map(\.title), ["Lantern Courier", "Paper Moon Post"])
        let url = try XCTUnwrap(mock.lastRequest(containing: "series/new")?.url?.absoluteString)
        XCTAssertTrue(url.contains("library_id=\(manga)"), url)

        let updated = try await client().feed(.recentlyUpdated, limit: 10)
        XCTAssertEqual(updated, [])
        let all = try XCTUnwrap(mock.lastRequest(containing: "series/updated")?.url?.absoluteString)
        XCTAssertFalse(all.contains("library_id"), all)
    }

    func testSeveralLibrariesAreCommaSeparated() async throws {
        mock.on("GET", "api/v1/series/new", body: loadFixture("komga-series-new"))
        let added = try await client(scope: [manga, comics]).feed(.newlyAdded, limit: 10)
        XCTAssertEqual(added.count, 3)
        let url = try XCTUnwrap(mock.lastRequest(containing: "series/new")?.url?.absoluteString)
        XCTAssertTrue(url.contains("library_id=\(manga)%2C\(comics)"), url)
    }

    func testNothingPickedReturnsNothing() async throws {
        let items = try await client(scope: []).feed(.newlyAdded, limit: 10)
        XCTAssertEqual(items, [])
        let found = try await client(scope: []).search("lantern")
        XCTAssertEqual(found, [])
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testSearchUsesFullTextSearch() async throws {
        mock.on("POST", "api/v1/series/list", body: loadFixture("komga-series-list"))
        let items = try await client(scope: [manga]).search("  lantern ")
        XCTAssertEqual(items.first?.title, "Lantern Courier")
        let body = jsonBody(mock.lastRequest(containing: "series/list"))
        XCTAssertEqual(body["fullTextSearch"] as? String, "lantern")
        XCTAssertNotNil((body["condition"] as? [String: Any])?["libraryId"])
    }

    // MARK: Detail, pages, progress

    func testSeriesDetailMapsBooksToChapters() async throws {
        mock.on("GET", "api/v1/series/\(seriesID)", body: loadFixture("komga-series"))
        mock.on("POST", "api/v1/books/list", body: loadFixture("komga-series-books"))
        let detail = try await client().seriesDetail(seriesID)
        XCTAssertEqual(detail.summary.title, "Lantern Courier")
        XCTAssertEqual(detail.synopsis, "A courier crosses a city of lanterns.")
        // Komga stores genres in lower case.
        XCTAssertEqual(detail.genres, ["Adventure", "Fantasy"])
        XCTAssertEqual(detail.authors, ["Aiko Example", "Ren Sample"])
        XCTAssertEqual(detail.status, "Ongoing")

        XCTAssertEqual(detail.chapters.map(\.title), ["The First Delivery", "Lantern Courier v02"])
        XCTAssertEqual(detail.chapters.map(\.id), [bookID, "0SB719FFDC3VM"])
        XCTAssertEqual(detail.chapters.map(\.pageCount), [6, 5])
        XCTAssertEqual(detail.chapters.map(\.number), [1, 2])
        // Komga's page 3 (one-based) is index 2.
        XCTAssertEqual(detail.chapters[0].lastPageRead, 2)
        XCTAssertFalse(detail.chapters[0].isRead)
        XCTAssertEqual(detail.continueChapter?.id, bookID)

        let books = jsonBody(mock.lastRequest(containing: "books/list"))
        let condition = try XCTUnwrap((books["condition"] as? [String: Any])?["seriesId"] as? [String: Any])
        XCTAssertEqual(condition["value"] as? String, seriesID)
        XCTAssertTrue(mock.lastRequest(containing: "books/list")?.url?.absoluteString.contains("unpaged=true") ?? false)
    }

    func testChaptersFollowNumberSortAndSkipDeleted() throws {
        let json = """
        [{"id":"b","seriesId":"s","name":"Two","metadata":{"title":"","number":"2","numberSort":2},"media":{"pagesCount":10},
          "readProgress":{"page":10,"completed":true}},
         {"id":"a","seriesId":"s","name":"One","metadata":{"title":"Start","numberSort":1},"media":{"pagesCount":8}},
         {"id":"c","seriesId":"s","name":"Gone","metadata":{"numberSort":3},"deleted":true}]
        """
        let books = try HTTPClient.decode([KomgaBookDTO].self, from: Data(json.utf8))
        let chapters = KomgaClient.chapters(from: books, seriesRef: SeriesRef(serverID: config.id, seriesID: "s"))
        XCTAssertEqual(chapters.map(\.id), ["a", "b"])
        XCTAssertEqual(chapters.map(\.title), ["Start", "Book 2"])
        XCTAssertEqual(chapters[1].isRead, true)
        XCTAssertEqual(chapters[1].lastPageRead, 9)
        XCTAssertEqual(chapters[0].lastPageRead, 0)
    }

    func testPagesHaveSizesAndOneBasedURLs() async throws {
        mock.on("GET", "api/v1/books/\(bookID)/pages", body: loadFixture("komga-book-pages"))
        let chapter = Chapter(id: bookID, seriesRef: SeriesRef(serverID: config.id, seriesID: seriesID),
                              title: "The First Delivery", number: 1, pageCount: 6)
        let pages = try await client().pages(for: chapter)
        XCTAssertEqual(pages.count, 6)
        XCTAssertEqual(pages.first?.index, 0)
        XCTAssertEqual(pages.first?.url.absoluteString, "http://komga.local:25600/api/v1/books/\(bookID)/pages/1")
        XCTAssertEqual(pages.last?.url.absoluteString, "http://komga.local:25600/api/v1/books/\(bookID)/pages/6")
        XCTAssertEqual(pages[0].size, PageSize(width: 800, height: 1200))
        XCTAssertEqual(pages[3].size?.isWide, true, "page 4 is a two-page spread")
    }

    func testSaveProgressSendsOneBasedPage() async throws {
        mock.on("PATCH", "read-progress", status: 204, body: "")
        let chapter = Chapter(id: bookID, seriesRef: SeriesRef(serverID: config.id, seriesID: seriesID),
                              title: "x", number: 1, pageCount: 6)
        try await client().saveProgress(chapter: chapter, libraryID: manga, page: 2, completed: false)
        let request = try XCTUnwrap(mock.lastRequest(containing: "read-progress"))
        XCTAssertEqual(request.url?.absoluteString, "http://komga.local:25600/api/v1/books/\(bookID)/read-progress")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "KEY")
        XCTAssertEqual(jsonBody(request)["page"] as? Int, 3)
        XCTAssertNil(jsonBody(request)["completed"])

        try await client().saveProgress(chapter: chapter, libraryID: manga, page: 5, completed: true)
        let done = jsonBody(mock.lastRequest(containing: "read-progress"))
        XCTAssertEqual(done["completed"] as? Bool, true)
        XCTAssertNil(done["page"])
    }

    func testMarkUnreadDeletesReadProgress() async throws {
        mock.on("DELETE", "read-progress", status: 204, body: "")
        let ref = SeriesRef(serverID: config.id, seriesID: seriesID)
        let chapter = Chapter(id: bookID, seriesRef: ref, title: "x", number: 1, pageCount: 6)
        try await client().markUnread(chapters: [chapter])
        var request = try XCTUnwrap(mock.lastRequest(containing: "read-progress"))
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "http://komga.local:25600/api/v1/books/\(bookID)/read-progress")
        try await client().markSeriesUnread(seriesID)
        request = try XCTUnwrap(mock.lastRequest(containing: "read-progress"))
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "http://komga.local:25600/api/v1/series/\(seriesID)/read-progress")
    }

    func testFactoryMakesKomgaClient() {
        let made = MangaServerFactory.make(config: config, credential: ServerCredential(apiKey: "KEY"), transport: mock)
        XCTAssertTrue(made is KomgaClient)
    }

    // MARK: Server form

    func testDraftTakesAPIKeyOrEmailAndPassword() {
        var d = ServerDraft(kind: .komga, address: "komga.local:25600")
        XCTAssertEqual(d.validationMessage, "Enter an API key, or your Komga email and password.")
        d.username = "reader@example.org"
        XCTAssertEqual(d.validationMessage, "Enter both your Komga email and password.")
        d.password = "secret"
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.credential, ServerCredential(username: "reader@example.org", password: "secret"))
        d.apiKey = " abc "
        XCTAssertEqual(d.credential, ServerCredential(apiKey: "abc"))
        XCTAssertEqual(d.resolvedURL?.absoluteString, "http://komga.local:25600")
        XCTAssertFalse(d.absorbOPDS(), "Kavita OPDS parsing is Kavita-only")
    }

    func testKomgaIsOfferedWhenAddingAServer() {
        XCTAssertTrue(ServerKind.userAddable.contains(.komga))
        XCTAssertEqual(ServerKind.komga.categoryNoun, "Libraries")
        XCTAssertTrue(ServerKind.komga.requiresLogin)
    }
}

/// Loads `Tests/MangaCoreTests/Fixtures/<name>.<ext>`.
func loadFixture(_ name: String, ext: String = "json") -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
          let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Missing fixture \(name).\(ext)")
    }
    return text
}

/// The UI-test mock has to stay in step with the real client.
final class MockKomgaTransportTests: XCTestCase {
    let config = ServerConfig(kind: .komga, name: "Test Komga", baseURL: URL(string: "http://komga.test")!)

    func testClientBrowsesTheMock() async throws {
        let client = KomgaClient(config: config, apiKey: MockKomgaTransport.apiKey, username: nil, password: nil,
                                 transport: MockKomgaTransport())
        let hello = try await client.validate()
        XCTAssertEqual(hello, "Signed in to Komga 1.30.2 as reader@example.org")
        let libraries = try await client.categories()
        XCTAssertEqual(libraries.map(\.name), ["Comics", "Manga"])
        let manga = try XCTUnwrap(libraries.first { $0.name == "Manga" })
        let page = try await client.series(in: manga, page: 1, pageSize: 20)
        XCTAssertEqual(page.items.map(\.title), ["Lantern Courier", "Paper Moon Post"])
        let added = try await client.feed(.newlyAdded, limit: 10)
        XCTAssertEqual(added.count, 3)
        let found = try await client.search("harbor")
        XCTAssertEqual(found.map(\.title), ["Harbor Lights"])

        let detail = try await client.seriesDetail("s-lantern")
        XCTAssertEqual(detail.chapters.map(\.title), ["The First Delivery", "Night Market"])
        XCTAssertEqual(detail.genres, ["Adventure"])
        let pages = try await client.pages(for: detail.chapters[0])
        XCTAssertEqual(pages.count, 6)

        var reading = try await client.feed(.continueReading, limit: 10)
        XCTAssertEqual(reading, [])
        try await client.saveProgress(chapter: detail.chapters[0], libraryID: nil, page: 2, completed: false)
        reading = try await client.feed(.continueReading, limit: 10)
        XCTAssertEqual(reading.map(\.title), ["Lantern Courier"])
        let after = try await client.seriesDetail("s-lantern")
        XCTAssertEqual(after.chapters[0].lastPageRead, 2)

        try await client.markUnread(chapters: [after.chapters[0]])
        reading = try await client.feed(.continueReading, limit: 10)
        XCTAssertEqual(reading, [], "mark unread clears the book's progress")
        try await client.saveProgress(chapter: detail.chapters[1], libraryID: nil, page: 1, completed: false)
        try await client.markSeriesUnread("s-lantern")
        reading = try await client.feed(.continueReading, limit: 10)
        XCTAssertEqual(reading, [], "mark series unread clears every book")
    }

    func testMockRejectsAWrongKey() async {
        let client = KomgaClient(config: config, apiKey: "nope", username: nil, password: nil,
                                 transport: MockKomgaTransport())
        do {
            _ = try await client.validate()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
    }
}
