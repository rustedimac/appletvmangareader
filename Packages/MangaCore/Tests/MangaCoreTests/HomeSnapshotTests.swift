import XCTest
@testable import MangaCore

/// Home's rows outlive the Home view (`HomeSnapshot`): a Home rebuilt by a
/// theme change shows the rows it had while it reloads, instead of only
/// the fastest source. Titles are made up.
final class HomeSnapshotTests: XCTestCase {
    private let free = ServerConfig(kind: .freeLibrary, name: "Free Library", baseURL: URL(string: "https://free.invalid")!)
    private let kavita = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "https://kavita.invalid")!)

    private func section(_ server: ServerConfig, _ ids: [String]) -> HomeServerSection {
        let series = ids.map { SeriesSummary(ref: SeriesRef(serverID: server.id, seriesID: $0), title: "Lantern \($0)", coverURL: nil) }
        return HomeServerSection(server: server, rows: [HomeRow(feed: .recentlyUpdated, series: series)])
    }

    private func loaded(_ key: String) -> HomeSnapshot {
        var home = HomeSnapshot()
        var reload = home.beginReload(key: key, order: [free.id, kavita.id])
        home.receive(section(free, ["f1"]), in: &reload)
        home.receive(section(kavita, ["k1"]), in: &reload)
        home.finish(reload)
        return home
    }

    private func servers(_ home: HomeSnapshot, _ key: String) -> [String] {
        home.sections(for: key).map(\.server.name)
    }

    func testReloadForSameKeyKeepsEveryServerUntilItAnswers() {
        var home = loaded("k")
        // A rebuilt Home starts a new reload: every server's rows still show.
        var reload = home.beginReload(key: "k", order: [free.id, kavita.id])
        XCTAssertEqual(servers(home, "k"), ["Free Library", "Kavita"])
        XCTAssertTrue(home.isLoaded("k"), "no spinner while refreshing")

        // The fast built-in source answers first; Kavita's old rows stay, in order.
        home.receive(section(free, ["f2"]), in: &reload)
        XCTAssertEqual(servers(home, "k"), ["Free Library", "Kavita"])
        XCTAssertEqual(home.sections(for: "k")[0].rows[0].series.map(\.ref.seriesID), ["f2"])
        XCTAssertEqual(home.sections(for: "k")[1].rows[0].series.map(\.ref.seriesID), ["k1"])

        home.receive(section(kavita, ["k2"]), in: &reload)
        home.finish(reload)
        XCTAssertEqual(home.sections(for: "k")[1].rows[0].series.map(\.ref.seriesID), ["k2"])
    }

    func testOtherKeyNeverShowsOldRows() {
        var home = loaded("k")
        XCTAssertTrue(servers(home, "other").isEmpty)
        var reload = home.beginReload(key: "other", order: [kavita.id])
        XCTAssertTrue(servers(home, "other").isEmpty)
        XCTAssertTrue(servers(home, "k").isEmpty, "rows of the old key are dropped")
        XCTAssertFalse(home.isLoaded("other"))
        home.receive(section(kavita, ["k3"]), in: &reload)
        XCTAssertEqual(servers(home, "other"), ["Kavita"])
    }

    func testOnlyNewestReloadWrites() {
        var home = loaded("k")
        var old = home.beginReload(key: "k", order: [free.id, kavita.id])
        var new = home.beginReload(key: "k", order: [free.id, kavita.id])
        XCTAssertFalse(home.isCurrent(old))
        home.receive(section(kavita, ["stale"]), in: &old)
        XCTAssertEqual(home.sections(for: "k")[1].rows[0].series.map(\.ref.seriesID), ["k1"])
        home.receive(section(kavita, ["k4"]), in: &new)
        XCTAssertEqual(home.sections(for: "k")[1].rows[0].series.map(\.ref.seriesID), ["k4"])
    }
}
