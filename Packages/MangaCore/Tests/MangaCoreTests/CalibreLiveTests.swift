import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Runs `CalibreClient` against a real Calibre content server, and the OPDS
/// client against any catalog whose books are downloaded whole (Calibre,
/// Calibre-Web). Skipped unless `CALIBRE_LIVE_URL` is set (plus
/// `CALIBRE_LIVE_USER` / `CALIBRE_LIVE_PASSWORD` when the server needs a
/// login; Basic and Digest both work). The library needs at least one book
/// in a format the app reads.
///
///     CALIBRE_LIVE_URL=http://localhost:8080 CALIBRE_LIVE_USER=… CALIBRE_LIVE_PASSWORD=… swift test --filter CalibreLiveTests
final class CalibreLiveTests: XCTestCase {
    func testBrowseAndOpenEveryFormat() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["CALIBRE_LIVE_URL"], let url = URL(string: address) else {
            throw XCTSkip("Set CALIBRE_LIVE_URL to run against a real Calibre content server")
        }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("calibre-live-\(UUID())")
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = CalibreClient(config: ServerConfig(kind: .calibre, name: "Live", baseURL: url),
                                   username: env["CALIBRE_LIVE_USER"], password: env["CALIBRE_LIVE_PASSWORD"],
                                   archives: LocalArchiveCache(directory: cache), transport: URLSessionTransport())
        let opened = try await LiveServerWalk.run(client)
        XCTAssertTrue(opened.contains("EPUB") || opened.contains("Images") || opened.contains("PDF"))
    }
}
