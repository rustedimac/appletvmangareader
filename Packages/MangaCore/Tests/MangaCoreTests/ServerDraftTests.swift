import XCTest
@testable import MangaCore

final class ServerDraftTests: XCTestCase {
    func testNormalizesTypedAddresses() {
        XCTAssertEqual(ServerDraft.normalizedURL("kavita.local")?.absoluteString, "http://kavita.local")
        XCTAssertEqual(ServerDraft.normalizedURL(" suwayomi.local:4567/ ")?.absoluteString, "http://suwayomi.local:4567")
        XCTAssertEqual(ServerDraft.normalizedURL("HTTPS://example.com/kavita/")?.absoluteString, "https://example.com/kavita")
        XCTAssertEqual(ServerDraft.normalizedURL("192.168.1.20:5000")?.absoluteString, "http://192.168.1.20:5000")
        XCTAssertNil(ServerDraft.normalizedURL(""))
        XCTAssertNil(ServerDraft.normalizedURL("not a url"))
        XCTAssertNil(ServerDraft.normalizedURL("ftp://host"))
    }

    func testKavitaOPDSPasteFillsAddressAndKey() {
        var d = ServerDraft(kind: .kavita, address: "http://kavita.local/api/opds/abc-123")
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.resolvedURL?.absoluteString, "http://kavita.local")
        XCTAssertEqual(d.resolvedAPIKey, "abc-123")
        XCTAssertTrue(d.absorbOPDS())
        XCTAssertEqual(d.address, "http://kavita.local")
        XCTAssertEqual(d.apiKey, "abc-123")
        XCTAssertFalse(d.absorbOPDS())
        XCTAssertEqual(d.credential, ServerCredential(apiKey: "abc-123"))
    }

    func testKavitaNeedsAKey() {
        var d = ServerDraft(kind: .kavita, address: "kavita.local")
        XCTAssertFalse(d.isValid)
        XCTAssertNotNil(d.validationMessage)
        d.apiKey = "  key  "
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.credential?.apiKey, "key")
    }

    func testSuwayomiAuthIsOptionalButPaired() {
        var d = ServerDraft(kind: .suwayomi, address: "suwayomi.local")
        XCTAssertTrue(d.isValid)
        XCTAssertNil(d.credential)
        d.username = "john"
        XCTAssertFalse(d.isValid)
        d.password = "pw"
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.credential, ServerCredential(username: "john", password: "pw"))
        // OPDS parsing only applies to Kavita.
        d.address = "http://host/api/opds/key"
        XCTAssertFalse(d.absorbOPDS())
    }

    func testNameDefaultsToHost() {
        var d = ServerDraft(kind: .suwayomi, address: "suwayomi.local:4567")
        XCTAssertEqual(d.resolvedName, "suwayomi.local")
        d.name = " Home "
        XCTAssertEqual(d.resolvedName, "Home")
        XCTAssertNil(ServerDraft(kind: .suwayomi).config())
    }

    func testEditRoundTripKeepsID() {
        let config = ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://kavita.local")!)
        let d = ServerDraft(editing: config, credential: ServerCredential(apiKey: "k"), syncProgress: false)
        XCTAssertEqual(d.config(id: config.id), config)
        XCTAssertEqual(d.apiKey, "k")
        XCTAssertFalse(d.syncProgress)
    }

    func testProfileHelpers() {
        var s = AppState.initial()
        XCTAssertEqual(s.nextProfileName(), "Profile 2")
        s.addProfile(name: "Profile 2")
        s.addProfile(name: "Profile 4")
        XCTAssertEqual(s.nextProfileName(), "Profile 5")
        let server = ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://s")!)
        s.addServer(server)
        XCTAssertEqual(s.profilesSyncing(to: server.id).map(\.id), [s.profiles[0].id])
    }
    // MARK: Kavita address forms (fake keys only)

    func testKavitaAddressForms() {
        let key = "00000000-fake-key-0000"
        let cases: [(typed: String, base: String, key: String?)] = [
            ("http://kavita.local", "http://kavita.local", nil),
            ("http://kavita.local/", "http://kavita.local", nil),
            ("kavita.local", "http://kavita.local", nil),
            ("http://kavita.local:5000", "http://kavita.local:5000", nil),
            ("http://kavita.local:5000/", "http://kavita.local:5000", nil),
            ("http://kavita.local/api/opds", "http://kavita.local", nil),
            ("http://kavita.local/api/opds/", "http://kavita.local", nil),
            ("http://kavita.local:5000/api/opds/", "http://kavita.local:5000", nil),
            ("http://kavita.local/api/opds/\(key)", "http://kavita.local", key),
            ("http://kavita.local/api/opds/\(key)/", "http://kavita.local", key),
            ("http://kavita.local:5000/api/opds/\(key)", "http://kavita.local:5000", key),
            ("https://example.com/kavita/api/opds/\(key)", "https://example.com/kavita", key),
            ("  http://192.168.1.20:5000/api/opds/\(key)  ", "http://192.168.1.20:5000", key),
        ]
        for c in cases {
            let d = ServerDraft(kind: .kavita, address: c.typed)
            XCTAssertEqual(d.resolvedURL?.absoluteString, c.base, c.typed)
            XCTAssertEqual(d.resolvedAPIKey, c.key ?? "", c.typed)
            XCTAssertEqual(d.isValid, c.key != nil, c.typed)
        }
    }

    func testTypingPastOPDSURLNeverRewritesTheField() {
        // Typing is just setting `address`; nothing in the draft rewrites it
        // until absorbOPDS() runs on Return/Test/Save.
        var d = ServerDraft(kind: .kavita)
        var typed = ""
        for ch in "http://kavita.local/api/opds/fake" {
            typed.append(ch)
            d.address = typed
            _ = d.resolvedURL
            _ = d.resolvedAPIKey
            _ = d.validationMessage
            XCTAssertEqual(d.address, typed)
        }
        XCTAssertEqual(d.address, "http://kavita.local/api/opds/fake")
        XCTAssertEqual(d.resolvedAPIKey, "fake")
    }

    func testOPDSURLWithoutKeyThenKeyField() {
        // John's case: the OPDS URL without a key as the address, and the key typed separately.
        var d = ServerDraft(kind: .kavita, address: "http://kavita.local/api/opds/", apiKey: "fake-key")
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.config()?.baseURL.absoluteString, "http://kavita.local")
        XCTAssertEqual(d.credential, ServerCredential(apiKey: "fake-key"))
        XCTAssertTrue(d.absorbOPDS())
        XCTAssertEqual(d.address, "http://kavita.local")
        XCTAssertEqual(d.apiKey, "fake-key")
    }

    func testFullOPDSURLPastedIntoKeyField() {
        var d = ServerDraft(kind: .kavita, address: "http://kavita.local:5000",
                            apiKey: "http://kavita.local:5000/api/opds/fake-key")
        XCTAssertEqual(d.resolvedAPIKey, "fake-key")
        XCTAssertTrue(d.isValid)
        XCTAssertTrue(d.absorbOPDS())
        XCTAssertEqual(d.apiKey, "fake-key")

        let partial = ServerDraft(kind: .kavita, address: "kavita.local", apiKey: "api/opds/fake-key")
        XCTAssertEqual(partial.resolvedAPIKey, "fake-key")
        let plain = ServerDraft(kind: .kavita, address: "kavita.local", apiKey: " fake-key ")
        XCTAssertEqual(plain.resolvedAPIKey, "fake-key")
    }

    func testAbsorbLeavesPlainAddressAlone() {
        var d = ServerDraft(kind: .kavita, address: "http://kavita.local:5000", apiKey: "fake")
        XCTAssertFalse(d.absorbOPDS())
        XCTAssertEqual(d.address, "http://kavita.local:5000")
    }

    func testOtherKindsDropAPIPaths() {
        XCTAssertEqual(ServerDraft(kind: .suwayomi, address: "http://suwayomi.local:4567/api/graphql").resolvedURL?.absoluteString,
                       "http://suwayomi.local:4567")
        XCTAssertEqual(ServerDraft(kind: .komga, address: "komga.local:25600/api/v1/", apiKey: "k").resolvedURL?.absoluteString,
                       "http://komga.local:25600")
        XCTAssertEqual(ServerDraft(kind: .komga, address: "https://example.com/komga").resolvedURL?.absoluteString,
                       "https://example.com/komga")
        // OPDS catalogs keep their path.
        XCTAssertEqual(ServerDraft(kind: .opds, address: "books.local:8083/opds/").resolvedURL?.absoluteString,
                       "http://books.local:8083/opds")
        // Kavita's OPDS split never applies to other kinds.
        XCTAssertEqual(ServerDraft(kind: .komga, address: "http://host/api/opds/key", apiKey: "k").resolvedAPIKey, "k")
    }

    func testEveryKindHasAddressHelpWithAnExample() {
        for kind in ServerKind.userAddable {
            XCTAssertTrue(ServerDraft.addressHelp(for: kind).contains("for example"), kind.rawValue)
        }
    }

    // MARK: Connection error messages

    func testConnectionErrorsSayWhatToFix() {
        let url = URL(string: "http://kavita.local:5000")!
        let unreachable = ConnectionErrorMessage.describe(URLError(.cannotConnectToHost), kind: .kavita, url: url)
        XCTAssertTrue(unreachable.contains("Couldn't reach Kavita at kavita.local:5000"), unreachable)
        let unknownHost = ConnectionErrorMessage.describe(URLError(.cannotFindHost), kind: .kavita, url: url)
        XCTAssertTrue(unknownHost.contains("Couldn't find a server called kavita.local:5000"), unknownHost)
        let badKey = ConnectionErrorMessage.describe(MangaError.unauthorized, kind: .kavita, url: url)
        XCTAssertTrue(badKey.contains("rejected the API key"), badKey)
        let wrongServer = ConnectionErrorMessage.describe(MangaError.http(status: 404, body: ""), kind: .kavita, url: url)
        XCTAssertTrue(wrongServer.contains("doesn't look like Kavita"), wrongServer)
        let html = ConnectionErrorMessage.describe(MangaError.decoding("x"), kind: .komga, url: url)
        XCTAssertTrue(html.contains("doesn't look like Komga"), html)
        let badPassword = ConnectionErrorMessage.describe(MangaError.unauthorized, kind: .kavita, url: url, password: true)
        XCTAssertTrue(badPassword.contains("username or password"), badPassword)
        let suwayomiLogin = ConnectionErrorMessage.describe(MangaError.http(status: 401, body: ""), kind: .suwayomi, url: url)
        XCTAssertTrue(suwayomiLogin.contains("username or password"), suwayomiLogin)
    }
}
