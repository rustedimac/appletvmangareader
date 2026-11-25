import XCTest
@testable import MangaCore

final class HTTPClientTests: XCTestCase {
    func testURLBuildingSortsQueryAndDropsNils() throws {
        let c = HTTPClient(baseURL: URL(string: "http://h:1/base/")!, transport: MockTransport())
        let url = try c.url("/api/x", query: ["b": "2", "a": "1", "skip": nil])
        XCTAssertEqual(url.absoluteString, "http://h:1/base/api/x?a=1&b=2")
    }

    func testQueryValuesAreEscaped() throws {
        let c = HTTPClient(baseURL: URL(string: "http://h")!, transport: MockTransport())
        let url = try c.url("api/Search/search", query: ["queryString": "blue sky&co+1"])
        XCTAssertEqual(url.absoluteString, "http://h/api/Search/search?queryString=blue%20sky%26co%2B1")
    }

    func testStatusMapping() async {
        let mock = MockTransport()
        mock.on("GET", "/401", status: 401, body: "")
        mock.on("GET", "/500", status: 500, body: "oops")
        let c = HTTPClient(baseURL: URL(string: "http://h")!, transport: mock)
        do { _ = try await c.send(try c.request("GET", "/401")); XCTFail() } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
        do { _ = try await c.send(try c.request("GET", "/500")); XCTFail() } catch {
            XCTAssertEqual(error as? MangaError, .http(status: 500, body: "oops"))
        }
        do { _ = try await c.send(try c.request("GET", "/missing")); XCTFail() } catch {
            XCTAssertEqual(error as? MangaError, .notFound)
        }
    }

    func testDateParsing() {
        XCTAssertEqual(DateParsing.parse("2024-05-01T00:00:00Z"), Date(timeIntervalSince1970: 1_714_521_600))
        XCTAssertEqual(DateParsing.parse("2024-05-01T00:00:00.1234567")?.timeIntervalSince1970 ?? 0, 1_714_521_600.123, accuracy: 0.01)
        XCTAssertEqual(DateParsing.parse("1714521600"), Date(timeIntervalSince1970: 1_714_521_600))
        XCTAssertEqual(DateParsing.parse("1714521600000"), Date(timeIntervalSince1970: 1_714_521_600))
        XCTAssertNil(DateParsing.parse("garbage"))
    }
}
