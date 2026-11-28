import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Runs `SuwayomiClient` against a real Suwayomi server (read-only).
/// Skipped unless `SUWAYOMI_LIVE_URL` is set (plus `SUWAYOMI_LIVE_USER` /
/// `SUWAYOMI_LIVE_PASSWORD` when it has a login). The library needs a
/// series with downloaded or local chapters.
///
///     SUWAYOMI_LIVE_URL=http://localhost:4567 swift test --filter SuwayomiLiveTests
final class SuwayomiLiveTests: XCTestCase {
    func testBrowseAndOpenAChapter() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["SUWAYOMI_LIVE_URL"], let url = URL(string: address) else {
            throw XCTSkip("Set SUWAYOMI_LIVE_URL to run against a real Suwayomi server")
        }
        let client = SuwayomiClient(config: ServerConfig(kind: .suwayomi, name: "Live", baseURL: url),
                                    username: env["SUWAYOMI_LIVE_USER"], password: env["SUWAYOMI_LIVE_PASSWORD"],
                                    transport: URLSessionTransport())
        try await LiveServerWalk.run(client)
    }
}
