import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Runs `OPDSClient` against a real OPDS server. Skipped unless
/// `OPDS_LIVE_URL` is set (plus `OPDS_LIVE_USER` / `OPDS_LIVE_PASSWORD`
/// for basic auth). The catalog needs at least one book with pages.
///
///     OPDS_LIVE_URL=http://localhost:10801 OPDS_LIVE_USER=… OPDS_LIVE_PASSWORD=… swift test --filter OPDSLiveTests
final class OPDSLiveTests: XCTestCase {
    func testBrowseAndOpenABook() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["OPDS_LIVE_URL"], let url = URL(string: address) else {
            throw XCTSkip("Set OPDS_LIVE_URL to run against a real OPDS server")
        }
        let cache = try XCTUnwrap(FileManager.default.temporaryDirectory.appendingPathComponent("opds-live-\(UUID())"))
        let client = OPDSClient(config: ServerConfig(kind: .opds, name: "Live", baseURL: url),
                                username: env["OPDS_LIVE_USER"], password: env["OPDS_LIVE_PASSWORD"],
                                archives: LocalArchiveCache(directory: cache), transport: URLSessionTransport())
        let hello = try await client.validate()
        print("validate:", hello)
        let sections = try await client.categories()
        print("sections:", sections.map(\.name))
        XCTAssertFalse(sections.isEmpty)
        for feed in HomeFeed.allCases {
            let items = try await client.feed(feed, limit: 5)
            print("\(feed):", items.map(\.title))
        }

        // Find a series with a readable chapter.
        var opened = false
        for section in sections where !opened {
            let page = try await client.series(in: section, page: 1, pageSize: 20)
            for series in page.items.prefix(3) where !opened {
                let detail = try await client.seriesDetail(series.ref.seriesID)
                guard let chapter = detail.chapters.first else { continue }
                if chapter.format?.isText == true {
                    // EPUB and text books are downloaded and read on device.
                    let manifest = try await client.bookManifest(for: chapter)
                    let text = try await client.bookSection(0, of: chapter)
                    print("\(section.name) › \(detail.summary.title) › \(chapter.title): \(manifest.sectionCount) sections, "
                          + "picture book \(manifest.isImageOnly), \(text.blocks.count) blocks in the first")
                    XCTAssertGreaterThan(manifest.sectionCount, 0)
                    continue
                }
                let pages = try await client.pages(for: chapter)
                print("\(section.name) › \(detail.summary.title) › \(chapter.title): \(pages.count) pages, first \(pages.first?.url.absoluteString ?? "-")")
                XCTAssertFalse(pages.isEmpty)
                let (data, response) = try await URLSessionTransport().send(client.imageRequest(pages[0].url))
                XCTAssertEqual(response.statusCode, 200)
                XCTAssertGreaterThan(data.count, 100)
                opened = true
            }
        }
        XCTAssertTrue(opened, "no section had a readable book")

        let first = try XCTUnwrap(sections.first)
        if let anything = try await client.series(in: first, page: 1, pageSize: 20).items.first {
            let hits = try await client.search(String(anything.title.prefix(5)))
            print("search:", hits.map(\.title))
        }
        try? FileManager.default.removeItem(at: cache)
    }
}
