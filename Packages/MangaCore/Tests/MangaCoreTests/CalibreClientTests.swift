import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// `CalibreClient` against fixtures in the content server's `ajax` format
/// (`Fixtures/Calibre`, titles invented). `CalibreLiveTests` runs the same
/// client against a real server.
final class CalibreClientTests: XCTestCase {
    var mock: CalibreMock!
    var cacheDir: URL!
    let base = URL(string: "http://calibre.test:8080")!

    override func setUp() {
        mock = CalibreMock()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("calibre-\(UUID().uuidString)")
        mock.on("/ajax/library-info", fixture: "library-info")
        mock.on("/ajax/search/Test_Library", query: "query=lantern", fixture: "search-lantern")
        mock.on("/ajax/search/Test_Library", fixture: "search-all")
        mock.on("/ajax/search/Comics", data: Data(#"{"total_num":0,"book_ids":[]}"#.utf8))
        mock.on("/ajax/books/Test_Library", fixture: "books")
        mock.on("/get/CBZ/2/Test_Library", data: loadFixtureData("pages-stored", ext: "cbz"))
        mock.on("/get/EPUB/3/Test_Library", data: loadFixtureData("book-text", ext: "epub"))
        mock.on("/get/TXT/4/Test_Library", data: Data("Plain words.\n\nMore words.".utf8))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func client(user: String? = nil, scope: Set<String>? = nil) -> CalibreClient {
        CalibreClient(config: ServerConfig(kind: .calibre, name: "Calibre", baseURL: base), username: user,
                      password: user.map { _ in "pw" }, categoryScope: scope,
                      archives: LocalArchiveCache(directory: cacheDir), transport: mock)
    }

    let library = MangaCategory(id: "Test_Library", name: "Test Library")

    func testValidateAndLibraries() async throws {
        let c = client()
        let hello = try await c.validate()
        XCTAssertEqual(hello, "Connected to Calibre (2 libraries, 5 books in the main one)")
        let libraries = try await c.categories()
        XCTAssertEqual(libraries.map(\.name), ["Test Library", "Comics"], "the default library first")
        let scoped = try await client(scope: ["Comics"]).categories()
        XCTAssertEqual(scoped.map(\.id), ["Comics"])
    }

    func testSeriesGroupBooksAndSort() async throws {
        let c = client()
        let page = try await c.series(in: library, page: 1, pageSize: 50)
        XCTAssertEqual(page.items.map(\.title), ["Lantern Courier", "Odd Format", "Paper Notes", "The Lamp Keeper"])
        XCTAssertFalse(page.hasMore)
        let lantern = page.items[0]
        XCTAssertEqual(lantern.chapterCount, 2)
        XCTAssertEqual(lantern.countUnit, .book)
        XCTAssertEqual(lantern.libraryID, "Test_Library")
        XCTAssertEqual(lantern.coverURL?.absoluteString, "http://calibre.test:8080/get/thumb/2/Test_Library?sz=400x600",
                       "the first book's cover")
        XCTAssertEqual(page.items[3].format, .epub)
        XCTAssertEqual(page.items[2].format, .text)

        let added = try await c.series(in: library, page: 1, pageSize: 50, sort: .recentlyAdded)
        XCTAssertEqual(added.items.map(\.title), ["The Lamp Keeper", "Lantern Courier", "Paper Notes", "Odd Format"])
        let descending = try await c.series(in: library, page: 1, pageSize: 50, sort: .titleDescending)
        XCTAssertEqual(descending.items.first?.title, "The Lamp Keeper")

        let first = try await c.series(in: library, page: 1, pageSize: 3)
        XCTAssertTrue(first.hasMore)
        let second = try await c.series(in: library, page: 2, pageSize: 3)
        XCTAssertEqual(second.items.map(\.title), ["The Lamp Keeper"])
        XCTAssertFalse(second.hasMore)
        let past = try await c.series(in: library, page: 5, pageSize: 3)
        XCTAssertTrue(past.items.isEmpty)
        // The library was read once for all of that.
        XCTAssertEqual(mock.count("/ajax/books/"), 1)
        let books = try XCTUnwrap(mock.last("/ajax/books/"))
        let ids = URLComponents(url: books.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ids" }?.value
        XCTAssertEqual(ids, "3,1,2,4,5", "newest first, one batch")
    }

    func testSeriesDetailAndFormats() async throws {
        let c = client()
        let page = try await c.series(in: library, page: 1, pageSize: 50)
        let lantern = try await c.seriesDetail(page.items[0].ref.seriesID)
        XCTAssertEqual(lantern.chapters.map(\.title), ["Lantern Courier 1", "Lantern Courier 2"], "series order")
        XCTAssertEqual(lantern.chapters.map(\.id), ["c:Test_Library:2", "c:Test_Library:1"])
        XCTAssertEqual(lantern.chapters.map(\.format), [nil, nil], "CBZ reads as pages")
        XCTAssertEqual(lantern.genres, ["Comics"])
        let count = try await c.chapterCount(seriesID: page.items[0].ref.seriesID)
        XCTAssertEqual(count, SeriesCount(count: 2, unit: .book))

        let lamp = try await c.seriesDetail(page.items[3].ref.seriesID)
        XCTAssertEqual(lamp.chapters.map(\.title), ["The Lamp Keeper"])
        XCTAssertEqual(lamp.chapters[0].format, .epub, "EPUB beats PDF")
        XCTAssertEqual(lamp.synopsis, "A keeper & a lamp.")
        XCTAssertEqual(lamp.genres, ["Fiction", "Night"])
        XCTAssertEqual(lamp.authors, ["Test Author"])
    }

    func testOpeningBooks() async throws {
        let c = client()
        let page = try await c.series(in: library, page: 1, pageSize: 50)
        let lantern = try await c.seriesDetail(page.items[0].ref.seriesID)
        let pages = try await c.pages(for: lantern.chapters[0])
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages[0].url.isFileURL)
        XCTAssertNotNil(mock.last("/get/CBZ/2/"))

        let lamp = try await c.seriesDetail(page.items[3].ref.seriesID)
        let manifest = try await c.bookManifest(for: lamp.chapters[0])
        XCTAssertEqual(manifest.title, "The Lamp Keeper")
        XCTAssertEqual(manifest.sectionCount, 2)
        let section = try await c.bookSection(1, of: lamp.chapters[0])
        XCTAssertEqual(section.blocks.first?.plainText, "The Storm")

        let notes = try await c.seriesDetail(page.items[2].ref.seriesID)
        let text = try await c.bookSection(0, of: notes.chapters[0])
        XCTAssertEqual(text.blocks.map(\.plainText), ["Plain words.", "More words."])

        let odd = try await c.seriesDetail(page.items[1].ref.seriesID)
        do {
            _ = try await c.pages(for: odd.chapters[0])
            XCTFail("MOBI isn't read")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("MOBI"), error.localizedDescription)
        }
    }

    func testFeedsAndSearch() async throws {
        let c = client()
        let added = try await c.feed(.newlyAdded, limit: 2)
        XCTAssertEqual(added.map(\.title), ["The Lamp Keeper", "Lantern Courier"])
        XCTAssertNotNil(added[0].feedDate)
        let continuing = try await c.feed(.continueReading, limit: 5)
        XCTAssertTrue(continuing.isEmpty, "progress is local")
        let found = try await c.search("lantern")
        XCTAssertEqual(found.map(\.title), ["Lantern Courier"])
    }

    func testContentFiltersUseTags() async throws {
        let c = client()
        let facets = try await c.contentFacets()
        XCTAssertEqual(facets.genres, ["Comics", "Fiction", "Night", "Notes"])
        let hidden = try await c.hiddenSeriesIDs(for: ContentFilter(hiddenGenres: ["Night"]))
        XCTAssertEqual(hidden, ["b:Test_Library:3"])
        let none = try await c.hiddenSeriesIDs(for: .none)
        XCTAssertTrue(none.isEmpty)
    }

    func testLoginAndProgress() async throws {
        let c = client(user: "reader")
        _ = try await c.validate()
        let header = mock.last("/ajax/library-info")?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(header, "Basic " + Data("reader:pw".utf8).base64EncodedString())
        let cover = c.imageRequest(URL(string: "http://calibre.test:8080/get/thumb/1/Test_Library")!)
        XCTAssertNotNil(cover.value(forHTTPHeaderField: "Authorization"))
        let elsewhere = c.authorize(URLRequest(url: URL(string: "http://other.test/x.jpg")!))
        XCTAssertNil(elsewhere.value(forHTTPHeaderField: "Authorization"))

        let before = mock.requests.count
        let chapter = Chapter(id: "c:Test_Library:1", seriesRef: SeriesRef(serverID: c.config.id, seriesID: "x"),
                              title: "x", number: 1, pageCount: 3)
        try await c.saveProgress(chapter: chapter, libraryID: nil, page: 1, completed: false)
        XCTAssertEqual(mock.requests.count, before, "nothing sent")
        XCTAssertFalse(ServerKind.calibre.canSyncProgress)
    }

    func testIDs() {
        let series = CalibreSeriesID(library: "My Books", kind: .series("Re: Zero: Part 1/2"))
        XCTAssertEqual(CalibreSeriesID(series.rawValue), series)
        let book = CalibreSeriesID(library: "Test_Library", kind: .book(42))
        XCTAssertEqual(book.rawValue, "b:Test_Library:42")
        XCTAssertEqual(CalibreSeriesID(book.rawValue), book)
        XCTAssertNil(CalibreSeriesID("x:y:z"))
        let chapter = CalibreChapterID(library: "My Books", book: 7)
        XCTAssertEqual(CalibreChapterID(chapter.rawValue), chapter)
        XCTAssertNil(CalibreChapterID("c:lib:notanumber"))
    }

    func testDraftAndKind() {
        var d = ServerDraft(kind: .calibre, address: "calibre.local:8080/ajax")
        XCTAssertTrue(d.isValid, "the login is optional")
        XCTAssertEqual(d.resolvedURL?.absoluteString, "http://calibre.local:8080")
        XCTAssertNil(d.credential)
        d.username = "reader"
        XCTAssertFalse(d.isValid, "username without password")
        d.password = "pw"
        XCTAssertEqual(d.credential, ServerCredential(username: "reader", password: "pw"))
        XCTAssertEqual(ServerKind.calibre.categoryNoun, "Libraries")
        XCTAssertFalse(ServerKind.calibre.requiresLogin)
        XCTAssertTrue(MangaServerFactory.make(config: ServerConfig(kind: .calibre, name: "c", baseURL: base),
                                              credential: nil) is CalibreClient)
    }
}

/// Serves Calibre fixtures by path (prefix), optionally also matching a
/// query substring. Routes are tried in order. Records every request.
final class CalibreMock: HTTPTransport, @unchecked Sendable {
    private struct Route { var path: String; var query: String?; var data: Data }
    private let lock = NSLock()
    private var routes: [Route] = []
    private(set) var requests: [URLRequest] = []

    func on(_ path: String, query: String? = nil, fixture: String) {
        guard let url = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures/Calibre"),
              let data = try? Data(contentsOf: url) else { fatalError("Missing fixture Calibre/\(fixture).json") }
        on(path, query: query, data: data)
    }

    func on(_ path: String, query: String? = nil, data: Data) {
        lock.withLock { routes.append(Route(path: path, query: query, data: data)) }
    }

    func count(_ path: String) -> Int { lock.withLock { requests.filter { $0.url?.path.hasPrefix(path) == true }.count } }

    func last(_ path: String) -> URLRequest? { lock.withLock { requests.last { $0.url?.path.hasPrefix(path) == true } } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let route: Route? = lock.withLock {
            requests.append(request)
            return routes.first { r in
                url.path.hasPrefix(r.path) && (r.query.map { (url.query ?? "").contains($0) } ?? true)
            }
        }
        guard let route else {
            return (Data("not found".utf8), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        return (route.data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
