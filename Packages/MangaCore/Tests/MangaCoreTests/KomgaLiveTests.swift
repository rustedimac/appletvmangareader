import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Runs `KomgaClient` against a real Komga server. Skipped unless
/// `KOMGA_LIVE_URL` is set, plus `KOMGA_LIVE_API_KEY` or
/// `KOMGA_LIVE_EMAIL` / `KOMGA_LIVE_PASSWORD`. The server needs at least one
/// library with a series. Progress is saved and then put back.
///
///     KOMGA_LIVE_URL=http://localhost:25600 KOMGA_LIVE_API_KEY=… swift test --filter KomgaLiveTests
final class KomgaLiveTests: XCTestCase {
    func makeClient() throws -> KomgaClient {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["KOMGA_LIVE_URL"], let url = URL(string: address) else {
            throw XCTSkip("Set KOMGA_LIVE_URL to run against a real Komga")
        }
        let config = ServerConfig(kind: .komga, name: "Live Komga", baseURL: url)
        return KomgaClient(config: config, apiKey: env["KOMGA_LIVE_API_KEY"], username: env["KOMGA_LIVE_EMAIL"],
                           password: env["KOMGA_LIVE_PASSWORD"], transport: URLSessionTransport())
    }

    func testBrowseReadAndSaveProgress() async throws {
        let client = try makeClient()
        let hello = try await client.validate()
        XCTAssertTrue(hello.hasPrefix("Signed in to Komga"), hello)

        let libraries = try await client.categories()
        XCTAssertFalse(libraries.isEmpty)
        // A series whose first book reads as pages (text EPUBs have no
        // Komga pages; they're downloaded, see the walk below).
        var found: SeriesSummary?
        search: for library in libraries {
            for item in try await client.series(in: library, page: 1, pageSize: 20).items {
                let first = try await client.seriesDetail(item.ref.seriesID).chapters.first
                if let first, first.format?.isText != true { found = item; break search }
            }
        }
        let series = try XCTUnwrap(found, "no library has a series")

        for feed in HomeFeed.allCases { _ = try await client.feed(feed, limit: 5) }
        let hits = try await client.search(String(series.title.prefix(4)))
        XCTAssertTrue(hits.contains { $0.ref == series.ref }, "search didn't find \(series.title)")

        let detail = try await client.seriesDetail(series.ref.seriesID)
        let chapter = try XCTUnwrap(detail.chapters.first)
        let pages = try await client.pages(for: chapter)
        XCTAssertEqual(pages.count, chapter.pageCount)
        XCTAssertFalse(pages.isEmpty)

        // The first page and the cover load with the client's login.
        for url in [pages[0].url, series.coverURL].compactMap({ $0 }) {
            let (data, response) = try await URLSessionTransport().send(client.imageRequest(url))
            XCTAssertEqual(response.statusCode, 200, url.absoluteString)
            XCTAssertFalse(data.isEmpty)
        }

        // Save page 2, read it back, then restore.
        let page = min(1, max(0, chapter.pageCount - 1))
        try await client.saveProgress(chapter: chapter, libraryID: series.libraryID, page: page, completed: false)
        let after = try await client.seriesDetail(series.ref.seriesID).chapters.first { $0.id == chapter.id }
        XCTAssertEqual(after?.lastPageRead, page)
        try await client.saveProgress(chapter: chapter, libraryID: series.libraryID, page: chapter.lastPageRead,
                                      completed: chapter.isRead)
    }

    /// Every format, text EPUBs included (downloaded and read on device).
    func testEveryFormatOpens() async throws {
        try await LiveServerWalk.run(try makeClient())
    }
}
