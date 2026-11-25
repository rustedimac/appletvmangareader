import XCTest
@testable import MangaCore

final class FavoritesSortTests: XCTestCase {
    let kavita = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local")!)
    let suwayomi = ServerConfig(kind: .suwayomi, name: "Attic Suwayomi", baseURL: URL(string: "http://suwayomi.local")!)

    /// Four favorites with distinct values for every key:
    /// - favorited: B newest, D, A, C oldest
    /// - updated: D newest, B, C, A oldest
    /// - last read: C newest, A; B and D never
    /// - unread: C 9, D 6, A 4, B unknown
    /// - server: C on "Attic Suwayomi", the rest on "Kavita"
    func makeState() -> (AppState, UUID) {
        var s = AppState.initial()
        s.addServer(kavita)
        s.addServer(suwayomi)
        let p = s.profiles[0].id
        let t = Date(timeIntervalSince1970: 1_000_000)
        func add(_ id: String, _ title: String, server: ServerConfig, favorited: Double, updated: Double, unread: Int?) {
            let summary = SeriesSummary(ref: SeriesRef(serverID: server.id, seriesID: id), title: title, coverURL: nil)
            s.setFavorite(summary, true, profile: p, now: t.addingTimeInterval(favorited))
            let chapters = (0..<(unread ?? 0)).map {
                Chapter(id: "\(id)-\($0)", seriesRef: summary.ref, title: "C", number: Double($0), pageCount: 1,
                        updatedAt: t.addingTimeInterval(updated))
            }
            if unread != nil {
                let detail = SeriesDetail(summary: summary, synopsis: nil, authors: [], genres: [], status: nil, chapters: chapters)
                s.updateFavorite(from: detail, profile: p, now: t)
            }
        }
        add("a", "Alpha", server: kavita, favorited: 30, updated: 100, unread: 4)
        add("b", "beta", server: kavita, favorited: 40, updated: 300, unread: nil)
        add("c", "Gamma", server: suwayomi, favorited: 10, updated: 200, unread: 9)
        add("d", "Delta 10", server: kavita, favorited: 35, updated: 400, unread: 6)
        // B has no chapters loaded, so give its update date directly.
        s.mutateData(p) { data in
            let i = data.favorites.firstIndex { $0.series.ref.seriesID == "b" }!
            data.favorites[i].latestChapterAt = t.addingTimeInterval(300)
        }
        s.recordProgress(SeriesRef(serverID: suwayomi.id, seriesID: "c"), chapterID: "c-0", page: 1, completed: false,
                         profile: p, now: t.addingTimeInterval(900))
        s.recordProgress(SeriesRef(serverID: kavita.id, seriesID: "a"), chapterID: "a-0", page: 1, completed: false,
                         profile: p, now: t.addingTimeInterval(500))
        return (s, p)
    }

    func order(_ key: FavoritesSortKey, ascending: Bool? = nil) -> String {
        var (s, p) = makeState()
        s.setFavoritesSort(FavoritesSort(key: key, ascending: ascending ?? key.defaultAscending), profile: p)
        return s.sorted(s.favorites(profile: p), profile: p).map(\.series.ref.seriesID).joined()
    }

    func testEachKeyInItsNaturalDirection() {
        XCTAssertEqual(order(.dateFavorited), "bdac")
        XCTAssertEqual(order(.title), "abdc", "case-insensitive A to Z")
        XCTAssertEqual(order(.latestChapter), "dbca")
        XCTAssertEqual(order(.lastRead), "cabd", "never read last, by title")
        XCTAssertEqual(order(.unread), "cdab", "unknown last")
        XCTAssertEqual(order(.server), "cabd", "Attic before Kavita, then title")
    }

    func testReversedDirections() {
        XCTAssertEqual(order(.dateFavorited, ascending: true), "cadb")
        XCTAssertEqual(order(.title, ascending: false), "cdba")
        XCTAssertEqual(order(.latestChapter, ascending: true), "acbd")
        XCTAssertEqual(order(.lastRead, ascending: true), "acbd", "never read still last")
        XCTAssertEqual(order(.unread, ascending: true), "adcb", "unknown still last")
    }

    func testDefaultIsNewestFavoritedFirst() {
        let (s, p) = makeState()
        XCTAssertEqual(s.favoritesSort(profile: p), .default)
        XCTAssertEqual(s.sorted(s.favorites(profile: p), profile: p).map(\.series.ref.seriesID).joined(), "bdac")
    }

    func testSelectingFlipsOrSwitches() {
        let sort = FavoritesSort.default
        XCTAssertEqual(sort.selecting(.title), FavoritesSort(key: .title, ascending: true))
        XCTAssertEqual(sort.selecting(.dateFavorited), FavoritesSort(key: .dateFavorited, ascending: true))
        XCTAssertEqual(sort.selecting(.unread), FavoritesSort(key: .unread, ascending: false))
        XCTAssertEqual(sort.reversed().reversed(), sort)
        XCTAssertEqual(FavoritesSort(key: .title, ascending: true).directionLabel, "A to Z")
        XCTAssertEqual(FavoritesSort(key: .lastRead, ascending: false).directionLabel, "Newest First")
    }

    func testSortIsPerProfile() {
        var (s, a) = makeState()
        let b = s.addProfile(name: "B").id
        s.setFavoritesSort(FavoritesSort(key: .title, ascending: false), profile: a)
        XCTAssertEqual(s.favoritesSort(profile: b), .default)
        XCTAssertEqual(s.favoritesSort(profile: a).key, .title)
    }

    func testUpdateFavoriteFromDetail() {
        var (s, p) = makeState()
        let ref = SeriesRef(serverID: kavita.id, seriesID: "a")
        var detail = SeriesDetail(summary: SeriesSummary(ref: ref, title: "Alpha", coverURL: nil, unreadCount: 77),
                                  synopsis: nil, authors: [], genres: [], status: nil,
                                  chapters: [Chapter(id: "x", seriesRef: ref, title: "X", number: 1, pageCount: 1, isRead: true,
                                                     updatedAt: Date(timeIntervalSince1970: 5))])
        detail.latestChapterAt = Date(timeIntervalSince1970: 99)
        let now = Date(timeIntervalSince1970: 2_000_000)
        s.updateFavorite(from: detail, profile: p, now: now)
        let f = s.favorites(profile: p).first { $0.series.ref == ref }!
        XCTAssertEqual(f.latestChapterAt, Date(timeIntervalSince1970: 99), "server value wins over chapter dates")
        XCTAssertEqual(f.unreadChapters, 0)
        XCTAssertEqual(f.series.unreadCount, 77)
        XCTAssertEqual(f.refreshedAt, now)

        // Not a favorite: nothing changes.
        let before = s
        let other = SeriesRef(serverID: kavita.id, seriesID: "zzz")
        s.updateFavorite(from: SeriesDetail(summary: SeriesSummary(ref: other, title: "Z", coverURL: nil), synopsis: nil,
                                            authors: [], genres: [], status: nil, chapters: []), profile: p)
        XCTAssertEqual(s, before)
    }

    func testRefreshAge() {
        var (s, p) = makeState()
        let t = Date(timeIntervalSince1970: 1_000_000)
        // B was never refreshed; the others were at t.
        XCTAssertEqual(s.favoritesNeedingRefresh(profile: p, maxAge: 3600, now: t.addingTimeInterval(60)).map(\.series.ref.seriesID), ["b"])
        XCTAssertEqual(s.favoritesNeedingRefresh(profile: p, maxAge: 3600, now: t.addingTimeInterval(7200)).count, 4)
        s.markFavoriteRefreshed(SeriesRef(serverID: kavita.id, seriesID: "b"), profile: p, now: t)
        XCTAssertTrue(s.favoritesNeedingRefresh(profile: p, maxAge: 3600, now: t.addingTimeInterval(60)).isEmpty)
    }

    func testLatestChapterDateFallsBackToChapters() {
        let ref = SeriesRef(serverID: kavita.id, seriesID: "a")
        let detail = SeriesDetail(summary: SeriesSummary(ref: ref, title: "A", coverURL: nil), synopsis: nil, authors: [],
                                  genres: [], status: nil, chapters: [
                                      Chapter(id: "1", seriesRef: ref, title: "1", number: 1, pageCount: 1, updatedAt: Date(timeIntervalSince1970: 10)),
                                      Chapter(id: "2", seriesRef: ref, title: "2", number: 2, pageCount: 1, updatedAt: Date(timeIntervalSince1970: 30)),
                                      Chapter(id: "3", seriesRef: ref, title: "3", number: 3, pageCount: 1),
                                  ])
        XCTAssertEqual(detail.latestChapterDate, Date(timeIntervalSince1970: 30))
    }
}
