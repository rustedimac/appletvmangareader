import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// EPUB, PDF and text files read on device (`LocalBookFiles.swift`,
/// `EPUBPackage`, `DownloadedBook`). The EPUB fixtures are stored (not
/// deflated) ZIPs so they unpack on every platform.
final class DownloadedBookTests: XCTestCase {
    var mock: FixtureTransport!
    var cacheDir: URL!
    var archives: LocalArchiveCache!

    override func setUp() {
        mock = FixtureTransport()
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("books-\(UUID().uuidString)")
        archives = LocalArchiveCache(directory: cacheDir)
        mock.on("/text.epub", data: loadFixtureData("book-text", ext: "epub"))
        mock.on("/pictures.epub", data: loadFixtureData("book-pictures", ext: "epub"))
        mock.on("/book.pdf", data: loadFixtureData("two-pages", ext: "pdf"))
        mock.on("/notes.txt", data: Data("First part.\n\nSecond part,\nwrapped.\n\n***\n\nThird.".utf8))
        mock.on("/fake.pdf", data: Data("<html>login page</html>".utf8))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func book(_ path: String, _ kind: ContentKind) -> DownloadedBook {
        DownloadedBook(request: URLRequest(url: URL(string: "http://books.test" + path)!), kind: kind,
                       archives: archives, transport: mock)
    }

    func testTextEPUBManifestTOCAndSections() async throws {
        let b = book("/text.epub", .epub)
        let manifest = try await b.manifest(title: "fallback")
        XCTAssertEqual(manifest.title, "The Lamp Keeper")
        XCTAssertEqual(manifest.sectionCount, 2)
        XCTAssertFalse(manifest.isImageOnly)
        // EPUB 3 nav: nested entries, anchors, the landmarks nav ignored.
        XCTAssertEqual(manifest.toc.map(\.title), ["One: The Hill", "Two: The Storm"])
        XCTAssertEqual(manifest.toc.map(\.section), [0, 1])
        XCTAssertEqual(manifest.toc[1].children.map(\.title), ["Night"])
        XCTAssertEqual(manifest.toc[1].children.first?.anchor, "night")

        let first = try await b.section(0)
        let text = first.blocks.map(\.plainText)
        XCTAssertEqual(text.first, "The Hill")
        XCTAssertFalse(text.contains { $0.contains("Head title") }, "the head isn't read as text")
        XCTAssertTrue(text.contains("A keeper climbed the long hill every evening."))
        let image = try XCTUnwrap(first.imageURLs.first)
        XCTAssertTrue(image.isFileURL)
        XCTAssertEqual(image.lastPathComponent, "lamp.png")
        XCTAssertEqual(FileManager.default.contents(atPath: image.path), Data("png lamp".utf8))

        let second = try await b.section(1)
        XCTAssertNotNil(second.blockIndex(forAnchor: "night"))
        // Read once, unpacked once.
        XCTAssertEqual(mock.requested.count, 1)
    }

    func testPictureEPUBReadsAsPages() async throws {
        let b = book("/pictures.epub", .epub)
        let manifest = try await b.manifest(title: "x")
        XCTAssertTrue(manifest.isImageOnly)
        XCTAssertEqual(manifest.toc.map(\.title), ["Page one", "Page two"], "EPUB 2 NCX")
        let pages = try await b.pages()
        XCTAssertEqual(pages.map { $0.url.lastPathComponent }, ["001.jpg", "002.jpg"])
        let (data, _) = try await URLSessionTransport().send(URLRequest(url: pages[1].url))
        XCTAssertEqual(data, Data("jpg 2".utf8))
    }

    func testPlainTextSplitsIntoSections() async throws {
        let b = book("/notes.txt", .text)
        let manifest = try await b.manifest(title: "Notes")
        XCTAssertEqual(manifest.title, "Notes")
        XCTAssertEqual(manifest.sectionCount, 1)
        let section = try await b.section(0)
        XCTAssertEqual(section.blocks.count, 4)
        XCTAssertTrue(section.blocks[1].plainText.hasPrefix("Second part,"))
        XCTAssertEqual(section.blocks[2], .rule)

        let long = (0..<30).map { "Paragraph \($0) " + String(repeating: "x", count: 2_000) }.joined(separator: "\n\n")
        let parts = DownloadedBook.textSections(long, size: 10_000)
        XCTAssertEqual(parts.count, 8, "four paragraphs per part")
        XCTAssertEqual(parts.joined(separator: "\n\n"), long, "nothing lost at the cuts")
    }

    func testNotAPDF() async {
        do {
            _ = try await book("/fake.pdf", .pdf).pages()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("PDF"), error.localizedDescription)
        }
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    func testPDFPagesAreDrawnOnFirstRead() async throws {
        let pages = try await book("/book.pdf", .pdf).pages()
        XCTAssertEqual(pages.map(\.size), [PageSize(width: 600, height: 900), PageSize(width: 900, height: 600)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pages[0].url.path), "drawn lazily")
        let (data, response) = try await URLSessionTransport().send(URLRequest(url: pages[0].url))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertTrue(FileManager.default.fileExists(atPath: pages[0].url.path))
    }
    #endif

    func testUnzipSkipsPathsOutsideTheFolder() throws {
        // A hand-made stored ZIP with "../evil.txt" and "ok/a.txt".
        let zip = Self.storedZip([("../evil.txt", "bad"), ("ok/a.txt", "good"), ("/abs.txt", "bad")])
        let folder = cacheDir.appendingPathComponent("unzip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LocalArchiveCache.unzipAll(zip, into: folder)
        XCTAssertEqual(FileManager.default.contents(atPath: folder.appendingPathComponent("ok/a.txt").path), Data("good".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("evil.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("abs.txt").path))
    }

    func testPDFPageURLs() {
        let folder = cacheDir.appendingPathComponent("x")
        let url = LocalPDFRenderer.pageURL(folder: folder, index: 12)
        XCTAssertEqual(url.lastPathComponent, "p0012.jpg")
        XCTAssertNil(LocalPDFRenderer.pageIndex(url), "no PDF in the folder")
        XCTAssertNil(LocalPDFRenderer.renderedPage(at: url))
    }

    /// A minimal stored ZIP (no compression), for path tests.
    static func storedZip(_ files: [(String, String)]) -> Data {
        var out = Data()
        var central = Data()
        func u16(_ data: inout Data, _ values: Int...) {
            for v in values { data.append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]) }
        }
        func u32(_ data: inout Data, _ values: Int...) {
            for v in values { u16(&data, v & 0xffff, (v >> 16) & 0xffff) }
        }
        for (name, text) in files {
            let nameData = Data(name.utf8), body = Data(text.utf8)
            let offset = out.count
            // Local file header.
            u32(&out, 0x04034b50)
            u16(&out, 20, 0, 0, 0, 0)
            u32(&out, 0, body.count, body.count)
            u16(&out, nameData.count, 0)
            out.append(nameData)
            out.append(body)
            // Central directory entry.
            u32(&central, 0x02014b50)
            u16(&central, 20, 20, 0, 0, 0, 0)
            u32(&central, 0, body.count, body.count)
            u16(&central, nameData.count, 0, 0, 0, 0)
            u32(&central, 0, offset)
            central.append(nameData)
        }
        let start = out.count
        out.append(central)
        u32(&out, 0x06054b50)
        u16(&out, 0, 0, files.count, files.count)
        u32(&out, central.count, start)
        u16(&out, 0)
        return out
    }
}
