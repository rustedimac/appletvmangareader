import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Basic and Digest logins (`PasswordAuth`), used by OPDS and Calibre.
final class PasswordAuthTests: XCTestCase {
    func testMD5Vectors() {
        XCTAssertEqual(MD5.hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(MD5.hex("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
        XCTAssertEqual(MD5.hex(String(repeating: "a", count: 1_000)), "cabe45dcc9ae5b66ba86600cca6b8ba8")
    }

    func testRFC2617Example() throws {
        let header = #"Digest realm="testrealm@host.com", qop="auth,auth-int", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41""#
        let challenge = try XCTUnwrap(DigestChallenge(header: header))
        XCTAssertEqual(challenge.realm, "testrealm@host.com")
        XCTAssertEqual(challenge.qop, "auth")
        let value = challenge.authorization(username: "Mufasa", password: "Circle Of Life", method: "GET",
                                            uri: "/dir/index.html", nonceCount: 1, cnonce: "0a4f113b")
        XCTAssertTrue(value.contains(#"response="6629fae49393a05397450978507c4ef1""#), value)
        XCTAssertTrue(value.contains("nc=00000001"))
        XCTAssertTrue(value.contains(#"opaque="5ccc069c403ebaf9f0171e9517f40e41""#))
    }

    func testChallengeParsing() {
        // Several schemes in one header; Calibre's shape.
        let both = #"Basic realm="calibre", Digest realm="calibre", nonce="abc", algorithm="MD5", qop="auth""#
        XCTAssertEqual(DigestChallenge(header: both)?.nonce, "abc")
        XCTAssertNil(DigestChallenge(header: #"Basic realm="x""#))
        XCTAssertNil(DigestChallenge(header: #"Digest realm="x", nonce="n", algorithm=SHA-512-256"#), "unsupported algorithm")
        XCTAssertEqual(DigestChallenge(header: #"Digest realm="x", nonce="n", stale=TRUE"#)?.stale, true)
        XCTAssertNil(DigestChallenge(header: #"Digest realm="x", nonce="n""#)?.qop, "RFC 2069 style")
    }

    func testURIIncludesQuery() {
        XCTAssertEqual(PasswordAuth.digestURI(URL(string: "http://h:8080/ajax/search/lib?num=10&sort=title")),
                       "/ajax/search/lib?num=10&sort=title")
        XCTAssertEqual(PasswordAuth.digestURI(URL(string: "http://h:8080")), "/")
        XCTAssertEqual(PasswordAuth.digestURI(URL(string: "http://h/get/EPUB/3/My%20Library")), "/get/EPUB/3/My%20Library")
    }

    func testTransportSwitchesToDigestAndRecoversFromStaleNonces() async throws {
        let server = DigestServer(user: "tester", password: "secret")
        let auth = PasswordAuth(username: "tester", password: "secret")
        let transport = PasswordAuthTransport(inner: server, auth: auth, host: "calibre.test")
        let url = URL(string: "http://calibre.test:8080/ajax/library-info")!
        let (_, first) = try await transport.send(URLRequest(url: url))
        XCTAssertEqual(first.statusCode, 200)
        XCTAssertTrue(auth.usesDigest)
        XCTAssertEqual(server.unauthorized, 1, "one 401 to learn the challenge")
        // Image requests made elsewhere get a Digest header straight away.
        XCTAssertTrue(auth.header(for: URLRequest(url: url)).hasPrefix("Digest "))
        let (_, second) = try await transport.send(URLRequest(url: url))
        XCTAssertEqual(second.statusCode, 200)
        XCTAssertEqual(server.unauthorized, 1)
        // The server rotates its nonce: one retry.
        server.nonce = "second"
        let (_, third) = try await transport.send(URLRequest(url: url))
        XCTAssertEqual(third.statusCode, 200)
        XCTAssertEqual(server.unauthorized, 2)
    }

    func testCalibreRejectsBasicWith400() async throws {
        let server = DigestServer(user: "tester", password: "secret")
        server.basicStatus = 400
        let auth = PasswordAuth(username: "tester", password: "secret")
        let transport = PasswordAuthTransport(inner: server, auth: auth, host: "calibre.test")
        let (_, response) = try await transport.send(URLRequest(url: URL(string: "http://calibre.test:8080/opds")!))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(auth.usesDigest)
    }

    func testWrongPasswordDoesNotLoop() async throws {
        let server = DigestServer(user: "tester", password: "secret")
        let transport = PasswordAuthTransport(inner: server, auth: PasswordAuth(username: "tester", password: "nope"),
                                              host: "calibre.test")
        let url = URL(string: "http://calibre.test:8080/ajax/library-info")!
        let (_, response) = try await transport.send(URLRequest(url: url))
        XCTAssertEqual(response.statusCode, 401)
        let (_, again) = try await transport.send(URLRequest(url: url))
        XCTAssertEqual(again.statusCode, 401)
        XCTAssertLessThanOrEqual(server.requests, 3, "no retry once the same challenge comes back")
    }

    func testOtherHostsGetNoLogin() async throws {
        let server = DigestServer(user: "u", password: "p")
        let transport = PasswordAuthTransport(inner: server, auth: PasswordAuth(username: "u", password: "p"), host: "calibre.test")
        _ = try await transport.send(URLRequest(url: URL(string: "http://cdn.example/cover.jpg")!))
        XCTAssertNil(server.lastAuthorization)
    }
}

/// A tiny Digest-only server: checks the response like Calibre does.
final class DigestServer: HTTPTransport, @unchecked Sendable {
    let user: String, password: String
    var nonce = "first"
    let realm = "calibre"
    /// What a Basic header gets (Calibre in Digest mode: 400).
    var basicStatus = 401
    private(set) var unauthorized = 0
    private(set) var requests = 0
    private(set) var lastAuthorization: String?

    init(user: String, password: String) {
        self.user = user
        self.password = password
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        let url = request.url!
        lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        if let header = lastAuthorization, header.hasPrefix("Digest ") {
            let p = DigestChallenge.parameters(String(header.dropFirst(7)))
            let ha1 = MD5.hex("\(user):\(realm):\(password)")
            let ha2 = MD5.hex("\(request.httpMethod ?? "GET"):\(p["uri"] ?? "")")
            let expected = MD5.hex("\(ha1):\(p["nonce"] ?? ""):\(p["nc"] ?? ""):\(p["cnonce"] ?? ""):auth:\(ha2)")
            if p["nonce"] == nonce, p["response"] == expected, p["uri"] == PasswordAuth.digestURI(url) {
                return (Data("{}".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        if lastAuthorization?.hasPrefix("Basic ") == true, basicStatus != 401 {
            return (Data("Unsupported authentication method".utf8),
                    HTTPURLResponse(url: url, statusCode: basicStatus, httpVersion: nil, headerFields: nil)!)
        }
        unauthorized += 1
        let challenge = #"Digest realm="\#(realm)", nonce="\#(nonce)", algorithm="MD5", qop="auth""#
        return (Data(), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil,
                                        headerFields: ["WWW-Authenticate": challenge])!)
    }
}
