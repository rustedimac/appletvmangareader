import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// OPDS fixtures were recorded from real Komga 1.30.2 and Stump servers
/// (loaded with code-drawn test pages, titles invented), except the
/// Calibre-Web one, which is hand-written in Calibre-Web's feed format.
final class OPDSParserTests: XCTestCase {
    let komga = URL(string: "http://komga.local:25600/opds/v1.2/series/0SB719FFDC3VJ")!
    let stump = URL(string: "http://stump.local:10801/opds/v1.2/series/0d6d970f-47f5-41d0-98a1-05b5a1c2992e")!

    func atom(_ name: String, base: URL) throws -> OPDSFeed {
        try OPDSParser.parse(Data(loadFixture(name, ext: "xml").utf8), contentType: "application/atom+xml", baseURL: base)
    }

    func testKomgaSeriesFeedHasPageStreaming() throws {
        let feed = try atom("opds1-komga-series", base: komga)
        XCTAssertEqual(feed.title, "Lantern Courier")
        XCTAssertEqual(feed.publications.count, 2)
        let book = feed.entries[0]
        XCTAssertEqual(book.title, "The First Delivery")
        XCTAssertEqual(book.id, "0SB719FFDC3VK")
        let pse = try XCTUnwrap(book.pseLink)
        XCTAssertEqual(pse.template, "http://komga.local:25600/opds/v1.2/books/0SB719FFDC3VK/pages/{pageNumber}")
        XCTAssertEqual(pse.pseCount, 6)
        XCTAssertEqual(pse.pseLastRead, 3)
        XCTAssertEqual(book.preferredAcquisition?.baseType, "application/zip")
        XCTAssertEqual(book.coverURL?.absoluteString, "http://komga.local:25600/opds/v1.2/books/0SB719FFDC3VK/thumbnail/small")
        XCTAssertNil(feed.entries[1].pseLink?.pseLastRead)
    }

    func testStumpRelativeLinksResolve() throws {
        let feed = try atom("opds1-stump-series", base: stump)
        let pse = try XCTUnwrap(feed.entries.first?.pseLink)
        XCTAssertEqual(pse.template,
                       "http://stump.local:10801/opds/v1.2/books/8d29a722-28da-4c0d-abb3-30f5511f3167/pages/{pageNumber}?zero_based=true")
        XCTAssertEqual(feed.entries.first?.coverURL?.absoluteString,
                       "http://stump.local:10801/opds/v1.2/books/8d29a722-28da-4c0d-abb3-30f5511f3167/thumbnail")
        let root = try atom("opds1-stump-root", base: URL(string: "http://stump.local:10801/opds/v1.2/catalog")!)
        XCTAssertEqual(root.navigationEntries.map(\.title),
                       ["Keep reading", "All series", "Latest series", "All libraries", "All books", "Latest books"])
        XCTAssertEqual(root.navigationEntries[1].navigationURL?.absoluteString, "http://stump.local:10801/opds/v1.2/series")
        XCTAssertEqual(root.searchLink?.href.absoluteString, "http://stump.local:10801/opds/v1.2/search")
    }

    func testCalibreWebAcquisitionOnlyFeed() throws {
        let feed = try atom("opds1-calibreweb-books", base: URL(string: "http://books.local:8083/opds/new")!)
        XCTAssertEqual(feed.publications.count, 2)
        let book = feed.entries[0]
        XCTAssertNil(book.pseLink)
        XCTAssertEqual(book.authors, ["Aiko Example"])
        XCTAssertEqual(book.categories, ["Comics"])
        XCTAssertEqual(book.summary, "A lighthouse keeper & her cat.")
        // CBZ is preferred over EPUB for reading pages.
        XCTAssertEqual(book.preferredAcquisition?.href.absoluteString, "http://books.local:8083/opds/download/12/cbz/")
        XCTAssertEqual(feed.entries[1].preferredAcquisition?.baseType, "application/pdf")
        XCTAssertEqual(feed.nextURL?.absoluteString, "http://books.local:8083/opds/new?offset=2")
        XCTAssertEqual(feed.searchLink?.baseType, "application/opensearchdescription+xml")
    }

    func testOPDS2PublicationsAndGroups() throws {
        let series = try OPDSParser.parse(Data(loadFixture("opds2-komga-series").utf8), contentType: "application/opds+json",
                                          baseURL: URL(string: "http://komga.local:25600/opds/v2/series/0SB719FFDC3VJ")!)
        let book = try XCTUnwrap(series.publications.first)
        XCTAssertEqual(book.title, "The First Delivery")
        XCTAssertEqual(book.numberOfPages, 6)
        XCTAssertEqual(book.divinaManifest?.absoluteString, "http://komga.local:25600/opds/v2/books/0SB719FFDC3VK/manifest")
        XCTAssertEqual(book.preferredAcquisition?.baseType, "application/vnd.comicbook+zip")
        XCTAssertEqual(book.coverURL?.absoluteString, "http://komga.local:25600/opds/v2/books/0SB719FFDC3VK/thumbnail")
        XCTAssertEqual(book.authors, ["Aiko Example", "Ren Sample"])
        let search = try XCTUnwrap(series.searchLink)
        XCTAssertEqual(search.template, "http://komga.local:25600/opds/v2/search{?query}")

        let root = try OPDSParser.parse(Data(loadFixture("opds2-komga-root").utf8), contentType: nil,
                                        baseURL: URL(string: "http://komga.local:25600/opds/v2/catalog")!)
        XCTAssertTrue(root.groups.map(\.title).contains("Keep Reading"))
        XCTAssertTrue(root.groups.contains { $0.title == "Libraries" && $0.entries.map(\.title) == ["Manga", "Comics"] })
        XCTAssertEqual(root.topLevel.map(\.title), ["Recommended", "Browse"])
    }

    func testOpenSearchTemplateResolvesRelative() {
        let data = Data(loadFixture("opds1-stump-opensearch", ext: "xml").utf8)
        let template = OPDSParser.openSearchTemplate(data, baseURL: URL(string: "http://stump.local:10801/opds/v1.2/search")!)
        XCTAssertEqual(template, "http://stump.local:10801/opds/v1.2/search/feed?search={searchTerms}")
        let komga = OPDSParser.openSearchTemplate(Data(loadFixture("opds1-komga-opensearch", ext: "xml").utf8),
                                                  baseURL: URL(string: "http://komga.local:25600/opds/v1.2/search")!)
        XCTAssertEqual(komga, "http://komga.local:25600/opds/v1.2/series?search={searchTerms}")
    }

    func testSearchTemplates() {
        XCTAssertEqual(OPDSClient.fillSearch("http://h/s?q={searchTerms}&p={startPage?}", "a%20b"), "http://h/s?q=a%20b&p=")
        XCTAssertEqual(OPDSClient.fillSearch("http://h/opds/v2/search{?query}", "x"), "http://h/opds/v2/search?query=x")
        XCTAssertEqual(OPDSClient.fillSearch("http://h/search?lang=en{?query}", "x"), "http://h/search?lang=en&query=x")
    }

    func testFormatSniffing() {
        XCTAssertEqual(OPDSParser.format(contentType: nil, data: Data("  <?xml version=\"1.0\"?><feed/>".utf8)), .atom)
        XCTAssertEqual(OPDSParser.format(contentType: nil, data: Data("{\"metadata\":{}}".utf8)), .json)
        XCTAssertNil(OPDSParser.format(contentType: nil, data: Data("<!doctype html><html></html>".utf8)))
        XCTAssertThrowsError(try OPDSParser.parse(Data("<html></html>".utf8), contentType: "text/html", baseURL: komga))
    }

    func testContentKinds() {
        XCTAssertEqual(ContentKind(mediaType: "application/x-cbz", url: nil), .comicArchive)
        XCTAssertEqual(ContentKind(mediaType: "", url: URL(string: "http://h/a.cbz")), .comicArchive)
        XCTAssertEqual(ContentKind(mediaType: "application/epub+zip", url: nil), .epub)
        XCTAssertEqual(ContentKind(mediaType: "application/octet-stream", url: URL(string: "http://h/a.pdf")), .pdf)
        XCTAssertEqual(ContentKind(mediaType: "application/x-cbr", url: nil), .other)
    }
}

final class OPDSClientTests: XCTestCase {
    let base = URL(string: "http://stump.local:10801")!
    var mock: FixtureTransport!
    var cacheDir: URL!

    override func setUp() {
        mock = FixtureTransport()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("opds-tests-\(UUID().uuidString)")
        let p = "/opds/v1.2/"
        // Most specific first.
        mock.on(p + "catalog", fixture: "opds1-stump-root")
        mock.on(p + "keep-reading", fixture: "opds1-stump-keep-reading")
        mock.on(p + "series/latest", fixture: "opds1-stump-series-latest")
        mock.on(p + "series/0d6d970f", fixture: "opds1-stump-series")
        mock.on(p + "series", fixture: "opds1-stump-series-list", exact: true)
        mock.on(p + "libraries/281ab025", fixture: "opds1-stump-library-281a")
        mock.on(p + "libraries/886eb9c6", fixture: "opds1-stump-library-886e")
        mock.on(p + "libraries", fixture: "opds1-stump-libraries", exact: true)
        mock.on(p + "books/latest", fixture: "opds1-stump-books-latest")
        mock.on(p + "books", fixture: "opds1-stump-books", exact: true)
        mock.on(p + "search/feed", fixture: "opds1-stump-books")
        mock.on(p + "search", fixture: "opds1-stump-opensearch", exact: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func client(_ url: URL? = nil, user: String? = "reader", scope: Set<String>? = nil) -> OPDSClient {
        OPDSClient(config: ServerConfig(kind: .opds, name: "Stump", baseURL: url ?? base), username: user,
                   password: user.map { _ in "pw" }, categoryScope: scope,
                   archives: LocalArchiveCache(directory: cacheDir), transport: mock)
    }

    func testFindsTheCatalogFromJustTheHost() async throws {
        let message = try await client().validate()
        XCTAssertEqual(message, "Connected to Stump OPDS catalog (6 sections)")
        let paths = mock.requested.map(\.path)
        XCTAssertEqual(paths.first, "", "the address itself is tried first")
        XCTAssertTrue(paths.contains("/opds/v1.2/catalog"))
        let auth = mock.requests.last?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(auth, "Basic " + Data("reader:pw".utf8).base64EncodedString())
    }

    func testWrongLoginStopsTheSearch() async {
        mock.status401 = true
        do {
            _ = try await client().validate()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
        XCTAssertEqual(mock.requests.count, 1, "a 401 means the catalog is there; don't keep probing")
    }

    func testSectionsExpandFoldersOfFolders() async throws {
        let sections = try await client().categories()
        // "Keep reading" is empty, so it's left out; "All libraries" holds
        // libraries of series, so its libraries become sections.
        XCTAssertEqual(sections.map(\.name),
                       ["All series", "Latest series", "All libraries › Comics", "All libraries › Manga", "All books", "Latest books"])
        XCTAssertEqual(sections[0].id, "http://stump.local:10801/opds/v1.2/series")
        let scoped = try await client(scope: [sections[0].id]).categories()
        XCTAssertEqual(scoped.map(\.name), ["All series"])
    }

    func testFolderSeriesListsItsBooksAsChapters() async throws {
        let c = client()
        let sections = try await c.categories()
        let page = try await c.series(in: sections[0], page: 1, pageSize: 20)
        XCTAssertEqual(page.items.map(\.title), ["Lantern Courier", "Paper Moon Post", "Harbor Lights"])
        XCTAssertEqual(page.items[0].libraryID, sections[0].id)

        let detail = try await c.seriesDetail(page.items[0].ref.seriesID)
        XCTAssertEqual(detail.summary.title, "Lantern Courier")
        XCTAssertEqual(detail.chapters.map(\.title), ["Lantern Courier v01", "Lantern Courier v02"])
        XCTAssertEqual(detail.chapters.map(\.pageCount), [6, 5])
        XCTAssertEqual(detail.summary.coverURL?.absoluteString,
                       "http://stump.local:10801/opds/v1.2/books/8d29a722-28da-4c0d-abb3-30f5511f3167/thumbnail")

        let pages = try await c.pages(for: detail.chapters[0])
        XCTAssertEqual(pages.count, 6)
        XCTAssertEqual(pages[0].url.absoluteString,
                       "http://stump.local:10801/opds/v1.2/books/8d29a722-28da-4c0d-abb3-30f5511f3167/pages/0?zero_based=true")
        XCTAssertEqual(pages[5].url.absoluteString,
                       "http://stump.local:10801/opds/v1.2/books/8d29a722-28da-4c0d-abb3-30f5511f3167/pages/5?zero_based=true")
    }

    func testBookEntriesAreOneChapterSeries() async throws {
        let c = client()
        let books = try await c.series(in: MangaCategory(id: "http://stump.local:10801/opds/v1.2/books", name: "All books"),
                                       page: 1, pageSize: 20)
        XCTAssertEqual(books.items.count, 4)
        let first = try XCTUnwrap(books.items.first)
        XCTAssertTrue(first.ref.seriesID.hasPrefix("b:"))
        let detail = try await c.seriesDetail(first.ref.seriesID)
        XCTAssertEqual(detail.chapters.count, 1)
        XCTAssertEqual(detail.chapters[0].title, first.title)
        XCTAssertGreaterThan(detail.chapters[0].pageCount, 0)
        // The id carries everything, so it works without the catalog.
        let pages = try await client().pages(for: detail.chapters[0])
        XCTAssertEqual(pages.count, detail.chapters[0].pageCount)
    }

    func testHomeRowsComeFromNamedSections() async throws {
        let c = client()
        let added = try await c.feed(.newlyAdded, limit: 10)
        XCTAssertEqual(added.map(\.title), ["Harbor Lights", "Lantern Courier", "Paper Moon Post"])
        let updated = try await c.feed(.recentlyUpdated, limit: 2)
        XCTAssertEqual(updated.map(\.title), ["Harbor Lights 001", "Lantern Courier v01"])
        let reading = try await c.feed(.continueReading, limit: 10)
        XCTAssertEqual(reading, [], "Keep reading is empty")
    }

    func testCategoryMatchingForHomeRows() {
        let names = ["Keep Reading", "On Deck", "All series", "Latest series", "Latest books", "All libraries › Manga"]
        let cats = names.map { MangaCategory(id: $0, name: $0) }
        XCTAssertEqual(OPDSClient.category(for: .continueReading, in: cats)?.name, "Keep Reading")
        XCTAssertEqual(OPDSClient.category(for: .newlyAdded, in: cats)?.name, "Latest series")
        XCTAssertEqual(OPDSClient.category(for: .recentlyUpdated, in: cats)?.name, "Latest books")
        let calibre = ["Recently added Books", "Hot Books", "Authors"].map { MangaCategory(id: $0, name: $0) }
        XCTAssertEqual(OPDSClient.category(for: .newlyAdded, in: calibre)?.name, "Recently added Books")
        XCTAssertNil(OPDSClient.category(for: .recentlyUpdated, in: calibre), "used once only")
    }

    func testSearchUsesOpenSearch() async throws {
        let results = try await client().search("lantern courier")
        XCTAssertEqual(results.count, 4)
        let url = try XCTUnwrap(mock.requested.last { $0.path.hasSuffix("search/feed") })
        XCTAssertEqual(url.absoluteString, "http://stump.local:10801/opds/v1.2/search/feed?search=lantern%20courier")
    }

    func testCBZOnlyBooksDownloadAndUnpack() async throws {
        mock.on("/opds/new", fixture: "opds1-calibreweb-books")
        mock.on("/opds/download/12/cbz", data: Data(loadFixtureData("pages-stored", ext: "cbz")))
        let c = client(URL(string: "http://stump.local:10801/opds/new")!)
        let items = try await c.series(in: MangaCategory(id: "http://stump.local:10801/opds/new", name: "New"), page: 1, pageSize: 20)
        let detail = try await c.seriesDetail(items.items[0].ref.seriesID)
        XCTAssertEqual(detail.synopsis, "A lighthouse keeper & her cat.")
        XCTAssertEqual(detail.authors, ["Aiko Example"])
        let pages = try await c.pages(for: detail.chapters[0])
        XCTAssertEqual(pages.map { $0.url.lastPathComponent }, ["0000.png", "0001.png"])
        XCTAssertTrue(pages[0].url.isFileURL)
        // Served by URLSessionTransport like any other image.
        let (data, response) = try await URLSessionTransport().send(URLRequest(url: pages[0].url))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "data a.png")
        // A second open uses the unpacked copy.
        let downloads = mock.requested.filter { $0.path.contains("download") }.count
        _ = try await c.pages(for: detail.chapters[0])
        XCTAssertEqual(mock.requested.filter { $0.path.contains("download") }.count, downloads)

        // PDFs aren't handled by this client yet.
        let pdf = try await c.seriesDetail(items.items[1].ref.seriesID)
        do {
            _ = try await c.pages(for: pdf.chapters[0])
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("PDF"), error.localizedDescription)
        }
    }

    func testPagingFollowsNextLinks() async throws {
        mock.on("/opds/new", fixture: "opds1-calibreweb-books")
        let c = client()
        let category = MangaCategory(id: "http://stump.local:10801/opds/new", name: "New")
        let first = try await c.series(in: category, page: 1, pageSize: 20)
        XCTAssertTrue(first.hasMore)
        _ = try await c.series(in: category, page: 2, pageSize: 20)
        XCTAssertEqual(mock.requested.last?.absoluteString, "http://stump.local:10801/opds/new?offset=2")
    }

    func testProgressIsLocalOnly() async throws {
        let chapter = Chapter(id: "c:x", seriesRef: SeriesRef(serverID: UUID(), seriesID: "f:x"), title: "x", number: 1, pageCount: 3)
        try await client().saveProgress(chapter: chapter, libraryID: nil, page: 1, completed: false)
        XCTAssertTrue(mock.requests.isEmpty)
        XCTAssertFalse(ServerKind.opds.canSyncProgress)
    }

    func testKomgaLastReadBecomesProgress() throws {
        let feed = try OPDSParser.parse(Data(loadFixture("opds1-komga-series", ext: "xml").utf8), contentType: nil,
                                        baseURL: URL(string: "http://komga.local:25600/opds/v1.2/series/x")!)
        let chapter = OPDSClient.chapter(OPDSBook(feed.entries[0]), seriesRef: SeriesRef(serverID: UUID(), seriesID: "f:x"), number: 1)
        XCTAssertEqual(chapter.pageCount, 6)
        XCTAssertEqual(chapter.lastPageRead, 2)
        XCTAssertFalse(chapter.isRead)
        // Ids are stable no matter what progress the feed reports.
        var other = feed.entries[0]
        other.links = other.links.map { var l = $0; l.pseLastRead = nil; return l }
        XCTAssertEqual(OPDSBook(other).chapterID, chapter.id)
    }

    func testDraftForOPDS() {
        var d = ServerDraft(kind: .opds, address: "books.local:8083/opds?lang=en")
        XCTAssertTrue(d.isValid, "no login needed")
        XCTAssertNil(d.credential)
        XCTAssertEqual(d.resolvedURL?.absoluteString, "http://books.local:8083/opds?lang=en")
        d.username = "reader"
        XCTAssertFalse(d.isValid)
        d.password = "pw"
        XCTAssertEqual(d.credential, ServerCredential(username: "reader", password: "pw"))
        XCTAssertTrue(ServerKind.userAddable.contains(.opds))
        XCTAssertEqual(ServerKind.opds.categoryNoun, "Sections")
    }
}

final class ZipArchiveTests: XCTestCase {
    func testStoredArchive() throws {
        let zip = try ZipArchive(data: loadFixtureData("pages-stored", ext: "cbz"))
        XCTAssertEqual(zip.imageEntries.map(\.path), ["a.png", "b.png"])
        XCTAssertEqual(String(decoding: try zip.extract(zip.imageEntries[1]), as: UTF8.self), "data b.png")
    }

    func testDeflatedArchiveSkipsJunkAndSortsNaturally() throws {
        let zip = try ZipArchive(data: loadFixtureData("pages-deflated", ext: "cbz"))
        XCTAssertEqual(zip.imageEntries.map(\.path), ["ch1/1.jpg", "ch1/2.jpg", "ch1/10.jpg"])
        #if canImport(Compression)
        let text = String(decoding: try zip.extract(zip.imageEntries[2]), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("page ch1/10.jpg page ch1/10.jpg"))
        #endif
    }

    func testNotAZip() {
        XCTAssertThrowsError(try ZipArchive(data: Data("hello".utf8))) { error in
            XCTAssertEqual(error as? ZipArchive.ZipError, .notAZip)
        }
    }
}

func loadFixtureData(_ name: String, ext: String) -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
          let data = try? Data(contentsOf: url) else {
        fatalError("Missing fixture \(name).\(ext)")
    }
    return data
}

/// Serves fixture files by URL path (prefix match, or exact). Anything else
/// is a 404. Records every request.
final class FixtureTransport: HTTPTransport, @unchecked Sendable {
    private struct Route { var path: String; var exact: Bool; var data: Data }
    private let lock = NSLock()
    private var routes: [Route] = []
    private(set) var requests: [URLRequest] = []
    var status401 = false

    var requested: [URL] { lock.withLock { requests.compactMap(\.url) } }

    func on(_ path: String, fixture: String, exact: Bool = false) {
        let ext = fixture.hasPrefix("opds2") ? "json" : "xml"
        on(path, data: Data(loadFixture(fixture, ext: ext).utf8), exact: exact)
    }

    func on(_ path: String, data: Data, exact: Bool = false) {
        lock.withLock { routes.append(Route(path: path, exact: exact, data: data)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let route: Route? = lock.withLock {
            requests.append(request)
            return routes.first { $0.exact ? url.path == $0.path : url.path.hasPrefix($0.path) }
        }
        if status401 { return (Data(), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!) }
        guard let route else {
            return (Data("<html>not found</html>".utf8), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        return (route.data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// The UI-test mock has to stay in step with the real client.
final class MockOPDSTransportTests: XCTestCase {
    func testClientBrowsesTheMock() async throws {
        let client = OPDSClient(config: ServerConfig(kind: .opds, name: "Test OPDS", baseURL: URL(string: "http://opds.test")!),
                                username: nil, password: nil, transport: MockOPDSTransport())
        let hello = try await client.validate()
        XCTAssertEqual(hello, "Connected to Test Catalog (2 sections)")
        let sections = try await client.categories()
        XCTAssertEqual(sections.map(\.name), ["Latest series", "All books"])
        let added = try await client.feed(.newlyAdded, limit: 10)
        XCTAssertEqual(added.map(\.title), ["Lantern Courier", "Paper Moon Post"])
        let detail = try await client.seriesDetail(added[0].ref.seriesID)
        XCTAssertEqual(detail.chapters.map(\.title), ["Lantern Courier 1", "Lantern Courier 2"])
        let pages = try await client.pages(for: detail.chapters[0])
        XCTAssertEqual(pages.map { $0.url.path }.last, "/opds/v1.2/books/lc1/pages/5")
        let found = try await client.search("paper")
        XCTAssertEqual(found.map(\.title), ["Paper Moon Post 1"])
    }
}
