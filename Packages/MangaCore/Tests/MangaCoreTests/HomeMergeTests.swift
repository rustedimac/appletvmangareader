import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Merged Home rows (`HomeMerge`), the Home server options in
/// `HomeLayout`, and where a series lives on its server (`SeriesPlacement`).
/// Titles are made up.
final class HomeMergeTests: XCTestCase {
    let a = UUID(), b = UUID(), c = UUID()

    private func s(_ server: UUID, _ id: String, _ date: TimeInterval? = nil) -> SeriesSummary {
        var series = SeriesSummary(ref: SeriesRef(serverID: server, seriesID: id), title: "Tide \(id)", coverURL: nil)
        series.feedDate = date.map { Date(timeIntervalSince1970: $0) }
        return series
    }

    private func ids(_ list: [SeriesSummary]) -> [String] { list.map(\.ref.seriesID) }

    // MARK: HomeMerge

    func testMergeOrdersByDateAcrossServers() {
        let merged = HomeMerge.merge([
            [s(a, "a1", 500), s(a, "a2", 300), s(a, "a3", 100)],
            [s(b, "b1", 400), s(b, "b2", 200)],
        ])
        XCTAssertEqual(ids(merged), ["a1", "b1", "a2", "b2", "a3"])
    }

    func testMergeWithoutDatesInterleavesByRankAndKeepsEachServersOrder() {
        let merged = HomeMerge.merge([
            [s(a, "a1"), s(a, "a2"), s(a, "a3")],
            [s(b, "b1")],
            [s(c, "c1"), s(c, "c2")],
        ])
        XCTAssertEqual(ids(merged), ["a1", "b1", "c1", "a2", "c2", "a3"])
    }

    func testMergeNeverReordersOneServersList() {
        // A server whose own order disagrees with its dates keeps its order.
        let merged = HomeMerge.merge([
            [s(a, "a1", 100), s(a, "a2", 900)],
            [s(b, "b1", 500)],
        ])
        XCTAssertEqual(ids(merged), ["b1", "a1", "a2"])
    }

    func testMergeMixedDatesFallsBackToRank() {
        // Free Library has no dates for some rows: rank decides against it.
        let merged = HomeMerge.merge([
            [s(a, "a1", 100), s(a, "a2", 50)],
            [s(b, "b1"), s(b, "b2")],
        ])
        XCTAssertEqual(ids(merged), ["a1", "b1", "a2", "b2"])
    }

    func testMergeDropsRepeatsAndHonoursLimit() {
        let merged = HomeMerge.merge([[s(a, "1", 3), s(a, "1", 2)], [s(b, "1", 1)]], limit: 5)
        XCTAssertEqual(merged.map(\.ref), [s(a, "1").ref, s(b, "1").ref], "same id on two servers are two series")
        XCTAssertEqual(HomeMerge.merge([[s(a, "1"), s(a, "2")], [s(b, "3")]], limit: 2).count, 2)
        XCTAssertEqual(HomeMerge.merge([]), [])
        XCTAssertEqual(HomeMerge.merge([[], []]), [])
    }

    // MARK: HomeLoader

    func testLoaderHandsOverFastServersFirst() async {
        let slow = SampleLibraryServer(config: ServerConfig(kind: .kavita, name: "Slow", baseURL: URL(string: "https://slow.invalid")!),
                                       seriesCount: 5, latency: .milliseconds(400))
        let fast = SampleLibraryServer(config: ServerConfig(kind: .suwayomi, name: "Fast", baseURL: URL(string: "https://fast.invalid")!),
                                       seriesCount: 5, latency: .milliseconds(10))
        var order: [Int] = []
        for await (index, section) in HomeLoader.each([HomeSource(server: slow), HomeSource(server: fast)]) {
            order.append(index)
            XCTAssertFalse(section.rows.isEmpty)
        }
        XCTAssertEqual(order, [1, 0], "the fast server's rows arrive without waiting for the slow one")
        let all = await HomeLoader.load([HomeSource(server: slow), HomeSource(server: fast)])
        XCTAssertEqual(all.map(\.server.name), ["Slow", "Fast"], "load keeps server order")
    }

    // MARK: HomeLayout

    func testServerOptionsDefaultToMergedAndUnderTitle() throws {
        let layout = HomeLayout()
        XCTAssertEqual(layout.serverRows, .merged)
        XCTAssertEqual(layout.serverLabel, .underTitle)
        XCTAssertTrue(layout.isDefault)
        // A layout saved before the options existed decodes to the defaults.
        let old = try JSONDecoder().decode(HomeLayout.self, from: Data(#"{"order":["newlyAdded"],"hidden":["caughtUp"]}"#.utf8))
        XCTAssertEqual(old.serverRows, .merged)
        XCTAssertEqual(old.serverLabel, .underTitle)
        XCTAssertEqual(old.rows.first, .newlyAdded)
        // Unknown values from a newer version don't break the layout.
        let newer = try JSONDecoder().decode(HomeLayout.self, from: Data(#"{"serverRows":"grid","serverLabel":"hover"}"#.utf8))
        XCTAssertEqual(newer.serverRows, .merged)
        XCTAssertEqual(newer.serverLabel, .underTitle)
    }

    func testServerOptionsRoundTripAndSurviveRowReset() throws {
        var layout = HomeLayout()
        layout.serverRows = .perServer
        layout.serverLabel = .onCover
        layout.move(.newlyAdded, by: -3)
        XCTAssertFalse(layout.isDefault)
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(decoded, layout)

        layout.resetRows()
        XCTAssertTrue(layout.rowsAreDefault)
        XCTAssertEqual(layout.serverRows, .perServer, "Reset Home Rows keeps the server options")
        XCTAssertEqual(layout.serverLabel, .onCover)
        XCTAssertFalse(layout.isDefault)

        // Default options aren't written, so older builds read the same JSON.
        let json = String(decoding: try JSONEncoder().encode(HomeLayout()), as: UTF8.self)
        XCTAssertFalse(json.contains("serverRows"))
        XCTAssertFalse(json.contains("serverLabel"))
    }

    func testServerOptionsArePerProfileAndSynced() throws {
        var state = AppState.initial()
        let first = try XCTUnwrap(state.activeProfile?.id)
        let second = state.addProfile(name: "Guest")
        state.updateBrowse(profile: first) { $0.home.serverRows = .perServer }
        XCTAssertEqual(state.browse(profile: first).home.serverRows, .perServer)
        XCTAssertEqual(state.browse(profile: second.id).home.serverRows, .merged)

        // The browse sync domain carries the Home server options.
        let records = SyncMapper.payloads(from: state).map { key, item in
            SyncRecord(key: key, kind: item.kind, payload: item.payload, modifiedAt: Date(), deviceID: "t")
        }
        var restored = AppState()
        SyncMapper.apply(SyncPatch(records: records), to: &restored)
        XCTAssertEqual(restored.browse(profile: first).home.serverRows, .perServer)
    }

    // MARK: SeriesPlacement

    func testPlacementResolvesIdsInServerOrder() {
        let categories = [MangaCategory(id: "9", name: "Webtoon", order: 2), MangaCategory(id: "0", name: "Default", order: 0),
                          MangaCategory(id: "4", name: "Reading", order: 1)]
        XCTAssertEqual(SeriesPlacement.resolve(ids: ["9", "4"], in: categories)?.categories, ["Reading", "Webtoon"])
        XCTAssertNil(SeriesPlacement.resolve(ids: ["77"], in: categories))
        XCTAssertNil(SeriesPlacement.resolve(ids: [], in: categories))
    }

    func testPlacementLine() {
        XCTAssertEqual(SeriesPlacement.line(server: "kavita.test", placement: SeriesPlacement(categories: ["Manga"])),
                       "kavita.test · Manga")
        XCTAssertEqual(SeriesPlacement.line(server: "suwayomi.test",
                                            placement: SeriesPlacement(categories: ["Reading", "Webtoon", "Reading", " "],
                                                                       source: "Example Source")),
                       "suwayomi.test · Reading, Webtoon · from Example Source")
        XCTAssertEqual(SeriesPlacement.line(server: "opds.test", placement: nil), "opds.test")
        XCTAssertNil(SeriesPlacement.line(server: nil, placement: SeriesPlacement(categories: [])))
    }

    func testPlacementFallsBackToTheServersCategories() async {
        let config = ServerConfig(kind: .kavita, name: "Demo", baseURL: URL(string: "https://demo.invalid")!)
        let server = SampleLibraryServer(config: config, seriesCount: 6, latency: .zero)
        let detail = try? await server.seriesDetail("3")
        let summary = SeriesSummary(ref: SeriesRef(serverID: config.id, seriesID: "3"), title: "x", coverURL: nil)
        let placement = await server.placement(for: summary, detail: detail)
        XCTAssertEqual(placement?.categories, ["All Series", "Every Third"], "a series in two libraries lists both")
        var known = detail
        known?.placement = SeriesPlacement(categories: ["From Detail"])
        let fromDetail = await server.placement(for: summary, detail: known)
        XCTAssertEqual(fromDetail?.categories, ["From Detail"])
    }
}
