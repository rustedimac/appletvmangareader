import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// A network where some hosts don't answer. Records every request.
final class FlakyNetwork: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var down: Set<String>
    private var slow: [String: Duration]
    private(set) var requests: [URLRequest] = []

    init(down: Set<String> = [], slow: [String: Duration] = [:]) {
        self.down = down
        self.slow = slow
    }

    func setDown(_ hosts: Set<String>) {
        lock.withLock { down = hosts }
    }

    var hosts: [String] { lock.withLock { requests.compactMap { $0.url?.host } } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let host = request.url?.host ?? ""
        let (isDown, delay) = lock.withLock { () -> (Bool, Duration?) in
            requests.append(request)
            return (down.contains(host), slow[host])
        }
        if let delay { try await Task.sleep(for: delay) }
        if isDown { throw URLError(.cannotConnectToHost) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"ok":true}"#.utf8), response)
    }
}

final class ServerAddressTests: XCTestCase {
    let home = URL(string: "http://kavita.home:5000")!
    let remote = URL(string: "https://manga.example.com/kavita")!

    var config: ServerConfig {
        ServerConfig(id: UUID(uuidString: "5A1D2C3B-AAAA-4E5F-8A9B-00000000000A")!, kind: .kavita, name: "Kavita",
                     baseURL: home, alternateURLs: [remote])
    }

    // MARK: Saved shape

    func testOldJSONWithoutAlternatesStillDecodes() throws {
        let json = #"{"baseURL":"http:\/\/kavita.local:5000","id":"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A","kind":"kavita","name":"Kavita"}"#
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.alternateURLs, [])
        XCTAssertEqual(decoded.addresses, [URL(string: "http://kavita.local:5000")!])
        XCTAssertFalse(decoded.hasAlternateAddresses)
    }

    func testOneAddressEncodesExactlyAsBefore() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let single = ServerConfig(id: config.id, kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
        XCTAssertEqual(String(decoding: try encoder.encode(single), as: UTF8.self),
                       #"{"baseURL":"http:\/\/kavita.local:5000","id":"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A","kind":"kavita","name":"Kavita"}"#)
        let round = try JSONDecoder().decode(ServerConfig.self, from: try encoder.encode(config))
        XCTAssertEqual(round, config)
        XCTAssertEqual(round.addresses, [home, remote])
    }

    func testAddressesDropRepeats() {
        var c = config
        c.alternateURLs = [home, remote, remote]
        XCTAssertEqual(c.addresses, [home, remote])
    }

    func testAlternatesTravelThroughSyncAndBackups() throws {
        var state = AppState.initial()
        state.addServer(config)
        let payloads = SyncMapper.payloads(from: state)
        let payload = try XCTUnwrap(payloads.values.first { $0.kind == .server }?.payload)
        let decoded = try XCTUnwrap(SyncMapper.decode(ServerConfig.self, payload))
        XCTAssertEqual(decoded.alternateURLs, [remote])
    }

    // MARK: Rewriting

    func testRewriteSwapsTheAddressPrefixOnly() {
        let api = URL(string: "http://kavita.home:5000/api/Series/12?x=1")!
        XCTAssertEqual(ServerAddressRouter.rewrite(api, for: config, to: remote).absoluteString,
                       "https://manga.example.com/kavita/api/Series/12?x=1")
        // Back the other way, e.g. a link the remote address handed out.
        let link = URL(string: "https://manga.example.com/kavita/api/image/1")!
        XCTAssertEqual(ServerAddressRouter.rewrite(link, for: config, to: home).absoluteString,
                       "http://kavita.home:5000/api/image/1")
        // Other hosts and look-alike prefixes are left alone.
        let elsewhere = URL(string: "https://covers.example.org/1.jpg")!
        XCTAssertEqual(ServerAddressRouter.rewrite(elsewhere, for: config, to: remote), elsewhere)
        let lookalike = URL(string: "http://kavita.home:50001/api")!
        XCTAssertEqual(ServerAddressRouter.rewrite(lookalike, for: config, to: remote), lookalike)
    }

    // MARK: Choosing an address

    func testUsesTheFirstAddressWhenItAnswers() async throws {
        let network = FlakyNetwork(slow: ["manga.example.com": .milliseconds(10)])
        let router = ServerAddressRouter()
        let transport = FailoverTransport(inner: network, config: config, router: router)
        _ = try await transport.send(URLRequest(url: home.appendingPathComponent("api/Library")))
        XCTAssertEqual(router.currentAddress(for: config), home)
        XCTAssertEqual(network.requests.last?.url?.absoluteString, "http://kavita.home:5000/api/Library")
    }

    func testFallsBackToTheNextAddressThatAnswers() async throws {
        let network = FlakyNetwork(down: ["kavita.home"])
        let store = InMemoryKeyValueStore()
        let router = ServerAddressRouter(store: store)
        let transport = FailoverTransport(inner: network, config: config, router: router)
        _ = try await transport.send(URLRequest(url: home.appendingPathComponent("api/Library")))
        XCTAssertEqual(network.requests.last?.url?.absoluteString, "https://manga.example.com/kavita/api/Library")
        XCTAssertEqual(router.currentAddress(for: config), remote)

        // Remembered across launches, so images go there before any check.
        let relaunched = ServerAddressRouter(store: store)
        XCTAssertEqual(relaunched.currentAddress(for: config), remote)
        XCTAssertEqual(relaunched.rewrite(home.appendingPathComponent("api/image"), for: config).host,
                       "manga.example.com")
    }

    func testWaitsForTheFirstAddressEvenWhenALaterOneIsFaster() async throws {
        let network = FlakyNetwork(slow: ["kavita.home": .milliseconds(200)])
        let router = ServerAddressRouter()
        let chosen = await router.resolve(config, transport: network)
        XCTAssertEqual(chosen, home)
    }

    func testSwitchesWhenTheAddressInUseStopsAnswering() async throws {
        let network = FlakyNetwork()
        let router = ServerAddressRouter()
        let transport = FailoverTransport(inner: network, config: config, router: router)
        _ = try await transport.send(URLRequest(url: home.appendingPathComponent("api/a")))
        XCTAssertEqual(router.currentAddress(for: config), home)

        network.setDown(["kavita.home"])
        _ = try await transport.send(URLRequest(url: home.appendingPathComponent("api/b")))
        XCTAssertEqual(network.requests.last?.url?.absoluteString, "https://manga.example.com/kavita/api/b")
        XCTAssertEqual(router.currentAddress(for: config), remote)
    }

    func testRechecksAfterAWhileSoHomeWinsAgain() async throws {
        let network = FlakyNetwork(down: ["kavita.home"])
        let clock = TestClock()
        let router = ServerAddressRouter(now: { clock.now })
        _ = await router.resolve(config, transport: network)
        XCTAssertEqual(router.currentAddress(for: config), remote)

        network.setDown([])
        _ = await router.resolve(config, transport: network)
        XCTAssertEqual(router.currentAddress(for: config), remote, "trusted until the recheck interval passes")
        clock.now += router.recheckInterval + 1
        _ = await router.resolve(config, transport: network)
        XCTAssertEqual(router.currentAddress(for: config), home)
    }

    func testNoAddressAnsweringIsAPlainError() async {
        let network = FlakyNetwork(down: ["kavita.home", "manga.example.com"])
        let transport = FailoverTransport(inner: network, config: config, router: ServerAddressRouter())
        do {
            _ = try await transport.send(URLRequest(url: home.appendingPathComponent("api/Library")))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MangaError, .unreachable(server: "Kavita", addresses: 2))
            XCTAssertTrue(ConnectionErrorText.message(for: error).contains("any of its 2 addresses"))
        }
    }

    func testOneAddressPassesStraightThrough() async throws {
        let network = FlakyNetwork(down: ["kavita.home"])
        let single = ServerConfig(kind: .kavita, name: "K", baseURL: home)
        let transport = FailoverTransport(inner: network, config: single, router: ServerAddressRouter())
        do {
            _ = try await transport.send(URLRequest(url: home))
            XCTFail("expected the network's own error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
        }
        XCTAssertEqual(network.requests.count, 1, "no checks for a single address")
    }

    func testServerErrorsDontSwitchAddresses() async throws {
        // A 401 from home means home answered: it's not a reason to move.
        final class Unauthorized: HTTPTransport, @unchecked Sendable {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }
        }
        let router = ServerAddressRouter()
        let transport = FailoverTransport(inner: Unauthorized(), config: config, router: router)
        let (_, response) = try await transport.send(URLRequest(url: home.appendingPathComponent("api/x")))
        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(router.currentAddress(for: config), home)
    }

    func testClientsGoThroughTheFailover() async throws {
        let network = FlakyNetwork(down: ["kavita.home"])
        let router = ServerAddressRouter()
        let client = MangaServerFactory.make(config: config, credential: ServerCredential(apiKey: "k"),
                                             transport: network, router: router)
        _ = try? await client.categories()
        XCTAssertTrue(network.hosts.contains("manga.example.com"))
        XCTAssertFalse(network.requests.contains { $0.url?.path.contains("/api/") == true && $0.url?.host == "kavita.home" },
                       "after the check, API calls skip the address that's down")
    }

    // MARK: Messages

    func testConnectionErrorsReadLikeSentences() {
        XCTAssertTrue(ConnectionErrorText.message(for: URLError(.cannotFindHost)).hasPrefix("That address couldn't be found"))
        XCTAssertTrue(ConnectionErrorText.message(for: URLError(.timedOut)).contains("too long"))
        XCTAssertEqual(ConnectionErrorText.message(for: MangaError.unauthorized), MangaError.unauthorized.errorDescription)
    }

    // MARK: Server form

    func testDraftParsesOtherAddresses() throws {
        var draft = ServerDraft(kind: .kavita, address: "kavita.home:5000", apiKey: "k",
                                alternateAddresses: ["https://manga.example.com/kavita/", "", "kavita.home:5000"])
        XCTAssertNil(draft.validationMessage)
        let saved = try XCTUnwrap(draft.config())
        XCTAssertEqual(saved.baseURL, home)
        XCTAssertEqual(saved.alternateURLs, [remote], "empty and repeated addresses are dropped")

        draft.alternateAddresses = ["not a url"]
        XCTAssertEqual(draft.validationMessage, "Address 2 doesn't look like a web address.")

        let editing = ServerDraft(editing: saved, credential: ServerCredential(apiKey: "k"), syncProgress: true)
        XCTAssertEqual(editing.alternateAddresses, ["https://manga.example.com/kavita"])
    }

    func testDraftAcceptsAKavitaOPDSURLAsAnotherAddress() throws {
        let draft = ServerDraft(kind: .kavita, address: "kavita.home:5000", apiKey: "k",
                                alternateAddresses: ["https://manga.example.com/kavita/api/opds/abc-123"])
        XCTAssertEqual(try XCTUnwrap(draft.config()).alternateURLs, [remote])
    }

    func testDraftOffersAtMostFourOtherAddresses() {
        var draft = ServerDraft()
        XCTAssertTrue(draft.canAddAlternateAddress)
        draft.alternateAddresses = ["a", "b", "c", "d"]
        XCTAssertFalse(draft.canAddAlternateAddress)
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
}
