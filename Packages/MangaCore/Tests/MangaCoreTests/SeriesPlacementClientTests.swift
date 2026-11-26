import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Each client reports which library/category a series is in (for series
/// detail) and the dates that order merged Home rows. Titles are made up.
final class SeriesPlacementClientTests: XCTestCase {
    var mock: MockTransport!

    override func setUp() {
        mock = MockTransport()
    }

    // MARK: Kavita

    private func kavita() -> KavitaClient {
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"reader","token":"jwt-1","refreshToken":"r","apiKey":"KEY"}"#)
        return KavitaClient(config: ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.test")!),
                            apiKey: "KEY", transport: mock)
    }

    func testKavitaDetailNamesTheLibrary() async throws {
        let client = kavita()
        mock.on("GET", "api/Series/7", body: #"{"id":7,"name":"Glass Harbor","libraryId":2,"libraryName":"Manga"}"#)
        mock.on("GET", "api/Series/volumes", body: "[]")
        let detail = try await client.seriesDetail("7")
        XCTAssertEqual(detail.placement, SeriesPlacement(categories: ["Manga"]))
    }

    func testKavitaFeedsCarryDates() async throws {
        let client = kavita()
        mock.on("POST", "api/Series/on-deck", body: """
        [{"id":1,"name":"Paper Kites","libraryId":2,"latestReadDate":"2026-11-24T10:00:00Z"},
         {"id":2,"name":"Salt Road","libraryId":2,"latestReadDate":"0001-01-01T00:00:00"}]
        """)
        mock.on("POST", "api/Series/recently-added-v2", body: #"[{"id":3,"name":"Moth Lantern","libraryId":2,"created":"2026-11-20T08:00:00Z"}]"#)
        mock.on("POST", "api/Series/recently-updated-series", body: #"[{"seriesId":4,"seriesName":"Iron Orchard","libraryId":2,"created":"2026-11-22T08:00:00Z"}]"#)
        let reading = try await client.feed(.continueReading, limit: 10)
        XCTAssertEqual(reading.first?.feedDate, ISO8601DateFormatter().date(from: "2026-11-24T10:00:00Z"))
        XCTAssertNil(reading.last?.feedDate, "0001-01-01 means never")
        let added = try await client.feed(.newlyAdded, limit: 10)
        XCTAssertEqual(added.first?.feedDate, ISO8601DateFormatter().date(from: "2026-11-20T08:00:00Z"))
        let updated = try await client.feed(.recentlyUpdated, limit: 10)
        XCTAssertEqual(updated.first?.feedDate, ISO8601DateFormatter().date(from: "2026-11-22T08:00:00Z"))
    }

    // MARK: Suwayomi

    private func suwayomi() -> SuwayomiClient {
        SuwayomiClient(config: ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.test")!),
                       username: nil, password: nil, transport: mock)
    }

    func testSuwayomiDetailNamesEveryCategoryAndTheSource() async throws {
        mock.onGraphQL("manga(id", body: """
        {"data":{"manga":{"id":4,"title":"Velvet Comet","unreadCount":0,
         "categories":{"nodes":[{"id":2,"name":"Reading"},{"id":5,"name":"Webtoon"}]},
         "source":{"displayName":"Example Source (EN)","name":"Example Source"},
         "chapters":{"nodes":[]}}}}
        """)
        let detail = try await suwayomi().seriesDetail("4")
        XCTAssertEqual(detail.placement?.categories, ["Reading", "Webtoon"])
        XCTAssertEqual(detail.placement?.source, "Example Source (EN)")
        XCTAssertEqual(detail.summary.categoryIDs, ["2", "5"])
        let query = String(decoding: mock.lastRequest(containing: "graphql")?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(query.contains("categories { nodes { id name } }"), query)
        XCTAssertTrue(query.contains("source { displayName name }"), query)
    }

    func testSuwayomiMangaInNoCategoryIsInDefault() async throws {
        mock.onGraphQL("manga(id", body: """
        {"data":{"manga":{"id":4,"title":"Velvet Comet","categories":{"nodes":[]},
         "source":{"displayName":"Local source"},"chapters":{"nodes":[]}}}}
        """)
        let detail = try await suwayomi().seriesDetail("4")
        XCTAssertEqual(detail.placement, SeriesPlacement(categories: ["Default"]), "the local source isn't named")
    }

    func testSuwayomiFeedsCarryDates() async throws {
        mock.onGraphQL("IN_LIBRARY_AT", body: #"{"data":{"mangas":{"nodes":[{"id":9,"title":"Quiet Signal","inLibraryAt":"1732400000"}]}}}"#)
        mock.onGraphQL("FETCHED_AT", body: #"{"data":{"chapters":{"nodes":[{"lastReadAt":"0","fetchedAt":"1732500000","manga":{"id":6,"title":"Fern Stair"}}]}}}"#)
        mock.onGraphQL("LAST_READ_AT", body: #"{"data":{"chapters":{"nodes":[{"lastReadAt":"1732300000","fetchedAt":"1","manga":{"id":7,"title":"Cobalt Bell"}}]}}}"#)
        let client = suwayomi()
        let added = try await client.feed(.newlyAdded, limit: 5)
        XCTAssertEqual(added.first?.feedDate, Date(timeIntervalSince1970: 1_732_400_000))
        let updated = try await client.feed(.recentlyUpdated, limit: 5)
        XCTAssertEqual(updated.first?.feedDate, Date(timeIntervalSince1970: 1_732_500_000))
        let reading = try await client.feed(.continueReading, limit: 5)
        XCTAssertEqual(reading.first?.feedDate, Date(timeIntervalSince1970: 1_732_300_000))
        XCTAssertNil(SuwayomiClient.date(nil))
        XCTAssertEqual(SuwayomiClient.date(try JSONDecoder().decode(FlexibleNumber.self, from: Data("1732300000000".utf8))),
                       Date(timeIntervalSince1970: 1_732_300_000), "milliseconds are understood too")
    }

    // MARK: Komga

    func testKomgaDetailNamesTheLibrary() async throws {
        let client = KomgaClient(config: ServerConfig(kind: .komga, name: "Test Komga", baseURL: URL(string: "http://komga.test")!),
                                 apiKey: MockKomgaTransport.apiKey, username: nil, password: nil,
                                 transport: MockKomgaTransport())
        let detail = try await client.seriesDetail("s-lantern")
        XCTAssertEqual(detail.placement, SeriesPlacement(categories: ["Manga"]))
    }

    // MARK: OPDS and others: names come from the summary's section

    func testFallbackUsesTheSectionTheSeriesWasOpenedFrom() async {
        let config = ServerConfig(kind: .opds, name: "Demo", baseURL: URL(string: "https://demo.invalid")!)
        let server = SampleLibraryServer(config: config, seriesCount: 3, latency: .zero)
        var opened = SeriesSummary(ref: SeriesRef(serverID: config.id, seriesID: "1"), title: "x", coverURL: nil)
        opened.libraryID = "short"
        let placement = await server.placement(for: opened, detail: nil)
        XCTAssertEqual(placement?.categories, ["Every Third"])
    }
}
