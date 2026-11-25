import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Kavita's EPUB API and format mapping. Response shapes follow Kavita's
/// `BookController`, `BookInfoDto`, `BookChapterItem` and `ChapterDto.files`.
final class KavitaBookTests: XCTestCase {
    let config = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
    var mock: MockTransport!
    var client: KavitaClient!
    lazy var ref = SeriesRef(serverID: config.id, seriesID: "7")

    override func setUp() {
        mock = MockTransport()
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"john","token":"jwt-1","apiKey":"KEY"}"#)
        client = KavitaClient(config: config, apiKey: "KEY", transport: mock)
    }

    func testManifestReadsInfoAndNestedTOC() async throws {
        mock.on("GET", "api/Book/42/book-info", body: #"{"bookTitle":"Alice's Adventures in Wonderland","seriesId":7,"volumeId":3,"seriesFormat":3,"seriesName":"Alice","chapterNumber":"-100000","volumeNumber":"-100000","libraryId":2,"pages":14,"isSpecial":false,"chapterTitle":""}"#)
        mock.on("GET", "api/Book/42/chapters", body: #"[{"title":"Chapter I","part":"","page":2,"children":[{"title":"The Pool of Tears","part":"pool","page":3,"children":[]}]},{"title":"Bad","part":null,"page":99,"children":null}]"#)
        let chapter = Chapter(id: "42", seriesRef: ref, title: "Volume 1", number: 1, pageCount: 14, format: .epub)
        let manifest = try await client.bookManifest(for: chapter)
        XCTAssertEqual(manifest.title, "Alice's Adventures in Wonderland")
        XCTAssertEqual(manifest.sectionCount, 14)
        XCTAssertEqual(manifest.toc, [
            BookTOCEntry(title: "Chapter I", section: 2, children: [BookTOCEntry(title: "The Pool of Tears", section: 3, anchor: "pool")]),
            BookTOCEntry(title: "Bad", section: 13),
        ])
        XCTAssertEqual(BookTOCEntry.flatten(manifest.toc).map(\.level), [0, 1, 0])
        let auth = mock.lastRequest(containing: "book-info")?.value(forHTTPHeaderField: "x-api-key")
        XCTAssertEqual(auth, "KEY")
    }

    func testManifestWithoutTOCStillOpens() async throws {
        mock.on("GET", "api/Book/42/book-info", body: #"{"bookTitle":"","pages":3}"#)
        mock.on("GET", "api/Book/42/chapters", status: 400, body: "epub-malformed")
        let chapter = Chapter(id: "42", seriesRef: ref, title: "Volume 1", number: 1, pageCount: 3, format: .epub)
        let manifest = try await client.bookManifest(for: chapter)
        XCTAssertEqual(manifest.title, "Volume 1")
        XCTAssertEqual(manifest.toc, [])
    }

    func testSectionDecodesJSONStringAndRewritesImageHost() async throws {
        let html = #"<div class="body"><h2>Down the Rabbit-Hole</h2><p>Alice was <i>very</i> tired.</p><img src="//kavita-internal:8080/api/book/42/book-resources?apiKey=IMG&file=images%2Ftenniel.png"/></div>"#
        let json = String(data: try JSONEncoder().encode(html), encoding: .utf8)!
        mock.on("GET", "api/Book/42/book-page?page=1", body: json)
        let chapter = Chapter(id: "42", seriesRef: ref, title: "Volume 1", number: 1, pageCount: 3, format: .epub)
        let section = try await client.bookSection(1, of: chapter)
        XCTAssertEqual(section.index, 1)
        XCTAssertEqual(section.blocks.map(\.plainText), ["Down the Rabbit-Hole", "Alice was very tired.", ""])
        XCTAssertEqual(section.imageURLs.map(\.absoluteString),
                       ["http://kavita.local:5000/api/book/42/book-resources?apiKey=IMG&file=images%2Ftenniel.png"])
    }

    func testSectionAcceptsPlainTextBody() {
        XCTAssertEqual(KavitaClient.decodeBookPage(Data("<p>Hi</p>".utf8)), "<p>Hi</p>")
        XCTAssertEqual(KavitaClient.decodeBookPage(Data(#" "<p>\"Hi\"</p>""#.utf8)), #"<p>"Hi"</p>"#)
    }

    func testResolveResourceKeepsReverseProxyPrefixFromKavita() {
        let base = URL(string: "https://home.example/kavita")!
        XCTAssertEqual(KavitaClient.resolveResource("//inner/kavita/api/book/1/book-resources?file=a.jpg", baseURL: base)?.absoluteString,
                       "https://home.example/kavita/api/book/1/book-resources?file=a.jpg")
        XCTAssertEqual(KavitaClient.resolveResource("api/x.png", baseURL: base)?.absoluteString,
                       "https://home.example/kavita/api/x.png")
        XCTAssertNil(KavitaClient.resolveResource("javascript:alert(1)", baseURL: base))
        XCTAssertNil(KavitaClient.resolveResource("  ", baseURL: base))
    }

    func testFormatsMapFromSeriesAndChapterFiles() async throws {
        mock.on("GET", "api/Series/7", body: #"{"id":7,"name":"Alice","libraryId":2,"format":3,"pages":14,"pagesRead":0}"#)
        mock.on("GET", "api/Series/volumes", body: #"""
        [{"id":3,"minNumber":-100000,"name":"-100000","chapters":[
          {"id":42,"range":"-100000","minNumber":-100000,"pages":14,"pagesRead":5,"files":[{"id":1,"filePath":"/books/alice.epub","pages":14,"format":3}]},
          {"id":43,"range":"-100000","minNumber":-100000,"pages":30,"pagesRead":0,"files":[{"id":2,"pages":30,"format":4}]},
          {"id":44,"range":"-100000","minNumber":-100000,"pages":2,"pagesRead":0}
        ]}]
        """#)
        mock.on("GET", "api/Series/metadata", body: #"{"summary":"","genres":[],"writers":[]}"#)
        let detail = try await client.seriesDetail("7")
        XCTAssertEqual(detail.summary.format, .epub)
        XCTAssertEqual(detail.chapters.map(\.format), [.epub, .pdf, .epub])
        XCTAssertEqual(detail.chapters.first?.lastPageRead, 5)
    }
}
