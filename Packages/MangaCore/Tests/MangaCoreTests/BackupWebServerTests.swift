import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class BackupWebServerTests: XCTestCase {
    func request(_ text: String) -> Data { Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8) }

    func testParseWaitsForTheWholeBody() {
        XCTAssertEqual(BackupHTTP.parse(request("GET /1/ HTTP/1.1\nHost: x\n")), .incomplete)
        XCTAssertEqual(BackupHTTP.parse(request("POST /1/restore HTTP/1.1\nContent-Length: 5\n\nab")), .incomplete)
        guard case .complete(let r) = BackupHTTP.parse(request("POST /1/restore HTTP/1.1\nContent-Length: 5\n\nabcde")) else {
            return XCTFail("expected a complete request")
        }
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/1/restore")
        XCTAssertEqual(r.body, Data("abcde".utf8))
        XCTAssertEqual(BackupHTTP.parse(request("POST /1/restore HTTP/1.1\nContent-Length: 999999999\n\n")), .invalid(413))
    }

    func route(_ method: String, _ path: String, body: Data = Data()) async -> BackupHTTP.Response {
        let r = BackupHTTP.Request(method: method, path: path, headers: [:], body: body)
        return await BackupHTTP.route(r, code: "123456", export: { Data("{\"b\":1}".utf8) },
                                      restore: { data in
                                          data == Data("good".utf8) ? .success("2 favorites") : .failure(MangaBackup.BackupError.notABackup)
                                      })
    }

    func testRoutesNeedTheCode() async {
        let wrongCode = await route("GET", "/000000/")
        XCTAssertEqual(wrongCode.status, 404)
        let root = await route("GET", "/")
        XCTAssertEqual(root.status, 404)
        let page = await route("GET", "/123456/")
        XCTAssertEqual(page.status, 200)
        XCTAssertTrue(String(decoding: page.body, as: UTF8.self).contains("/123456/backup.json"))
        let download = await route("GET", "/123456/backup.json")
        XCTAssertEqual(download.body, Data("{\"b\":1}".utf8))
        XCTAssertTrue(download.headers["Content-Disposition"]?.contains("attachment") ?? false)
        let restored = await route("POST", "/123456/restore", body: Data("good".utf8))
        XCTAssertEqual(restored.status, 200)
        let rejected = await route("POST", "/123456/restore", body: Data("bad".utf8))
        XCTAssertEqual(rejected.status, 422)
        let wrongMethod = await route("GET", "/123456/restore")
        XCTAssertEqual(wrongMethod.status, 405)
    }

    #if canImport(Network)
    func testServesOverTheNetwork() async throws {
        let server = BackupWebServer(code: "654321", export: { Data("{\"ok\":true}".utf8) },
                                     restore: { _ in .success("done") })
        let port = try await server.start(preferredPort: 0)
        defer { server.stop() }
        XCTAssertGreaterThan(port, 0)
        let url = URL(string: "http://127.0.0.1:\(port)/654321/backup.json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, Data("{\"ok\":true}".utf8))

        var post = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/654321/restore")!)
        post.httpMethod = "POST"
        post.httpBody = Data(repeating: 65, count: 300_000) // spans several reads
        let (answer, _) = try await URLSession.shared.data(for: post)
        XCTAssertEqual(String(decoding: answer, as: UTF8.self), "done")
    }
    #endif
}
