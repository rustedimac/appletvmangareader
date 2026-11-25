import XCTest
@testable import MangaCore

final class ServerDraftTests: XCTestCase {
    func testNormalizesTypedAddresses() {
        XCTAssertEqual(ServerDraft.normalizedURL("kavita.home")?.absoluteString, "http://kavita.home")
        XCTAssertEqual(ServerDraft.normalizedURL(" suwayomi.home:4567/ ")?.absoluteString, "http://suwayomi.home:4567")
        XCTAssertEqual(ServerDraft.normalizedURL("HTTPS://example.com/kavita/")?.absoluteString, "https://example.com/kavita")
        XCTAssertEqual(ServerDraft.normalizedURL("192.168.1.20:5000")?.absoluteString, "http://192.168.1.20:5000")
        XCTAssertNil(ServerDraft.normalizedURL(""))
        XCTAssertNil(ServerDraft.normalizedURL("not a url"))
        XCTAssertNil(ServerDraft.normalizedURL("ftp://host"))
    }

    func testKavitaOPDSPasteFillsAddressAndKey() {
        var d = ServerDraft(kind: .kavita, address: "http://kavita.home/api/opds/abc-123")
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.resolvedURL?.absoluteString, "http://kavita.home")
        XCTAssertEqual(d.resolvedAPIKey, "abc-123")
        XCTAssertTrue(d.absorbOPDS())
        XCTAssertEqual(d.address, "http://kavita.home")
        XCTAssertEqual(d.apiKey, "abc-123")
        XCTAssertFalse(d.absorbOPDS())
        XCTAssertEqual(d.credential, ServerCredential(apiKey: "abc-123"))
    }

    func testKavitaNeedsAKey() {
        var d = ServerDraft(kind: .kavita, address: "kavita.home")
        XCTAssertFalse(d.isValid)
        XCTAssertNotNil(d.validationMessage)
        d.apiKey = "  key  "
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.credential?.apiKey, "key")
    }

    func testSuwayomiAuthIsOptionalButPaired() {
        var d = ServerDraft(kind: .suwayomi, address: "suwayomi.home")
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
        var d = ServerDraft(kind: .suwayomi, address: "suwayomi.home:4567")
        XCTAssertEqual(d.resolvedName, "suwayomi.home")
        d.name = " Home "
        XCTAssertEqual(d.resolvedName, "Home")
        XCTAssertNil(ServerDraft(kind: .suwayomi).config())
    }

    func testEditRoundTripKeepsID() {
        let config = ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://kavita.home")!)
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
}
