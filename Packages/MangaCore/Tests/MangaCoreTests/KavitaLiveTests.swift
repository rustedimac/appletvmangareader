import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Runs `KavitaClient` against a real Kavita (read-only). Skipped unless
/// `KAVITA_LIVE_URL` and `KAVITA_LIVE_API_KEY` are set.
///
///     KAVITA_LIVE_URL=http://localhost:5005 KAVITA_LIVE_API_KEY=… swift test --filter KavitaLiveTests
final class KavitaLiveTests: XCTestCase {
    func testBrowseAndOpenEveryFormat() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["KAVITA_LIVE_URL"], let url = URL(string: address), let key = env["KAVITA_LIVE_API_KEY"] else {
            throw XCTSkip("Set KAVITA_LIVE_URL and KAVITA_LIVE_API_KEY to run against a real Kavita")
        }
        let client = KavitaClient(config: ServerConfig(kind: .kavita, name: "Live", baseURL: url), apiKey: key,
                                  transport: URLSessionTransport())
        try await LiveServerWalk.run(client)
    }
}
