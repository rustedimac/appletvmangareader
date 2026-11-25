import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class PhoneSetupTests: XCTestCase {
    let context = PhoneSetupHTTP.Context(kind: .kavita, name: "Den <TV>", address: "kavita.home:5000")

    func route(_ method: String, _ path: String, body: Data = Data(), contentType: String = "application/json",
               submit: (PhoneSetupHTTP.Submission) async -> Result<String, Error> = { _ in .success("ok") })
        async -> BackupHTTP.Response {
        let request = BackupHTTP.Request(method: method, path: path, headers: ["content-type": contentType], body: body)
        return await PhoneSetupHTTP.route(request, code: "123456", context: context, submit: submit)
    }

    func testOnlyTheCodeOpensThePage() async {
        let wrong = await route("GET", "/000000/")
        XCTAssertEqual(wrong.status, 404)
        let root = await route("GET", "/")
        XCTAssertEqual(root.status, 404)
        let page = await route("GET", "/123456/")
        XCTAssertEqual(page.status, 200)
        let html = String(decoding: page.body, as: UTF8.self)
        XCTAssertTrue(html.contains("/123456/submit"))
        XCTAssertTrue(html.contains(#"value="kavita.home:5000""#))
        XCTAssertTrue(html.contains("Den &lt;TV&gt;"), "typed text is escaped")
        XCTAssertTrue(html.contains(#"<option value="kavita" selected>"#))
        let wrongMethod = await route("GET", "/123456/submit")
        XCTAssertEqual(wrongMethod.status, 405)
    }

    func testSubmitHandsTheFormToTheTV() async throws {
        var received: PhoneSetupHTTP.Submission?
        let body = Data(#"{"kind":"komga","name":"Komga","address":"komga.home:25600","alternateAddresses":["https://komga.example.com"],"apiKey":"","username":"me@example.com","password":"pw"}"#.utf8)
        let response = await route("POST", "/123456/submit", body: body) { received = $0; return .success("Sent.") }
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "Sent.")
        let submission = try XCTUnwrap(received)

        var draft = ServerDraft()
        submission.apply(to: &draft, kindLocked: false)
        XCTAssertEqual(draft.kind, .komga)
        XCTAssertEqual(draft.address, "komga.home:25600")
        XCTAssertEqual(draft.alternateAddresses, ["https://komga.example.com"])
        XCTAssertEqual(draft.username, "me@example.com")
        XCTAssertEqual(draft.password, "pw")
        XCTAssertNil(draft.validationMessage)
    }

    func testAnEmptyAddressIsTurnedDown() async {
        var called = false
        let response = await route("POST", "/123456/submit", body: Data(#"{"address":"  "}"#.utf8)) { _ in
            called = true
            return .success("")
        }
        XCTAssertEqual(response.status, 400)
        XCTAssertFalse(called)
    }

    func testPlainFormPostsWorkToo() async throws {
        var received: PhoneSetupHTTP.Submission?
        let body = Data("kind=suwayomi&address=http%3A%2F%2Fsuwayomi.home%3A4567&alternateAddress=https%3A%2F%2Fa.example.com&alternateAddress=&username=reader+one&password=p%26w".utf8)
        let response = await route("POST", "/123456/submit", body: body,
                                   contentType: "application/x-www-form-urlencoded") { received = $0; return .success("ok") }
        XCTAssertEqual(response.status, 200)
        let s = try XCTUnwrap(received)
        XCTAssertEqual(s.kind, "suwayomi")
        XCTAssertEqual(s.address, "http://suwayomi.home:4567")
        XCTAssertEqual(s.username, "reader one")
        XCTAssertEqual(s.password, "p&w")
        var draft = ServerDraft()
        s.apply(to: &draft, kindLocked: false)
        XCTAssertEqual(draft.alternateAddresses, ["https://a.example.com"], "empty fields are dropped")
    }

    func testEditingKeepsTheTypeAndSplitsAKavitaOPDSURL() {
        let submission = PhoneSetupHTTP.Submission(kind: "suwayomi", address: "http://kavita.home:5000/api/opds/abc-123")
        var draft = ServerDraft(kind: .kavita)
        submission.apply(to: &draft, kindLocked: true)
        XCTAssertEqual(draft.kind, .kavita)
        XCTAssertEqual(draft.address, "http://kavita.home:5000")
        XCTAssertEqual(draft.apiKey, "abc-123")
    }

    func testUnknownTypesAreIgnored() {
        var draft = ServerDraft(kind: .opds)
        PhoneSetupHTTP.Submission(kind: "freeLibrary", address: "x.home").apply(to: &draft, kindLocked: false)
        XCTAssertEqual(draft.kind, .opds)
    }

    func testContextNeverCarriesSecrets() {
        let draft = ServerDraft(kind: .kavita, address: "kavita.home", apiKey: "secret-key", password: "pw")
        let page = PhoneSetupHTTP.page(code: "1", context: PhoneSetupHTTP.Context(draft: draft, kindLocked: true))
        XCTAssertFalse(page.contains("secret-key"))
        XCTAssertTrue(page.contains(#"id="kind" name="kind" disabled"#))
    }

    #if canImport(Network)
    func testServesOverTheNetwork() async throws {
        let server = PhoneSetupServer(code: "654321", context: context) { _ in .success("thanks") }
        let port = try await server.start(preferredPort: 0)
        defer { server.stop() }
        var post = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/654321/submit")!)
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.httpBody = Data(#"{"address":"kavita.home"}"#.utf8)
        let (answer, response) = try await URLSession.shared.data(for: post)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: answer, as: UTF8.self), "thanks")
    }
    #endif
}
