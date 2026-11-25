import XCTest
@testable import MangaCore

final class AppStateTests: XCTestCase {
    let kavita = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local")!)
    let suwayomi = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local")!)

    func testInitialStateHasOneActiveProfile() {
        let s = AppState.initial()
        XCTAssertEqual(s.profiles.count, 1)
        XCTAssertEqual(s.activeProfile?.id, s.profiles[0].id)
    }

    func testAddingServersSetsSyncDefaults() {
        var s = AppState.initial()
        let owner = s.profiles[0].id
        let second = s.addProfile(name: "Kid").id
        s.addServer(kavita)
        s.addServer(suwayomi)
        XCTAssertTrue(s.serverSettings(profile: owner, server: kavita.id).syncProgressToServer)
        XCTAssertTrue(s.serverSettings(profile: second, server: kavita.id).syncProgressToServer)
        XCTAssertTrue(s.serverSettings(profile: owner, server: suwayomi.id).syncProgressToServer)
        XCTAssertFalse(s.serverSettings(profile: second, server: suwayomi.id).syncProgressToServer)

        // A profile created after the Suwayomi server also defaults to local.
        let third = s.addProfile(name: "Guest").id
        XCTAssertFalse(s.serverSettings(profile: third, server: suwayomi.id).syncProgressToServer)
        XCTAssertTrue(s.serverSettings(profile: third, server: kavita.id).syncProgressToServer)
    }

    func testFavoritesAreSeparatePerProfile() {
        var s = AppState.initial()
        s.addServer(kavita)
        let a = s.profiles[0].id
        let b = s.addProfile(name: "B").id
        let series = SeriesSummary(ref: SeriesRef(serverID: kavita.id, seriesID: "7"), title: "Berserk", coverURL: nil)
        s.setFavorite(series, true, profile: a)
        XCTAssertTrue(s.isFavorite(series.ref, profile: a))
        XCTAssertFalse(s.isFavorite(series.ref, profile: b))
        s.setFavorite(series, true, profile: a) // no duplicates
        XCTAssertEqual(s.favorites(profile: a).count, 1)
        s.setFavorite(series, false, profile: a)
        XCTAssertTrue(s.favorites(profile: a).isEmpty)
    }

    func testFavoritesSortedNewestFirst() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let one = SeriesSummary(ref: SeriesRef(serverID: kavita.id, seriesID: "1"), title: "One", coverURL: nil)
        let two = SeriesSummary(ref: SeriesRef(serverID: kavita.id, seriesID: "2"), title: "Two", coverURL: nil)
        s.setFavorite(one, true, profile: p, now: Date(timeIntervalSince1970: 100))
        s.setFavorite(two, true, profile: p, now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(s.favorites(profile: p).map(\.series.title), ["Two", "One"])
    }

    func testProgressAndLocalOverlay() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let ref = SeriesRef(serverID: suwayomi.id, seriesID: "3")
        s.recordProgress(ref, chapterID: "10", page: 19, completed: true, profile: p)
        s.recordProgress(ref, chapterID: "11", page: 4, completed: false, profile: p)
        let progress = s.progress(ref, profile: p)
        XCTAssertEqual(progress?.chapterID, "11")
        XCTAssertEqual(progress?.page, 4)
        XCTAssertEqual(progress?.readChapterIDs, ["10"])

        let detail = SeriesDetail(
            summary: SeriesSummary(ref: ref, title: "X", coverURL: nil),
            synopsis: nil, authors: [], genres: [], status: nil,
            chapters: [
                Chapter(id: "10", seriesRef: ref, title: "1", number: 1, pageCount: 20),
                Chapter(id: "11", seriesRef: ref, title: "2", number: 2, pageCount: 20),
            ])
        let merged = s.applyingLocalProgress(to: detail, profile: p)
        XCTAssertTrue(merged.chapters[0].isRead)
        XCTAssertFalse(merged.chapters[1].isRead)
        XCTAssertEqual(merged.chapters[1].lastPageRead, 4)
        XCTAssertEqual(merged.continueChapter?.id, "11")
    }

    func testRemovingServerCleansProfiles() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        s.addServer(kavita)
        s.addServer(suwayomi)
        let ref = SeriesRef(serverID: kavita.id, seriesID: "1")
        let other = SeriesRef(serverID: suwayomi.id, seriesID: "1")
        s.setFavorite(SeriesSummary(ref: ref, title: "A", coverURL: nil), true, profile: p)
        s.setFavorite(SeriesSummary(ref: other, title: "B", coverURL: nil), true, profile: p)
        s.recordProgress(ref, chapterID: "1", page: 1, completed: false, profile: p)
        s.setReaderSettings(.webtoonDefault, for: ref, profile: p)
        s.removeServer(kavita.id)
        XCTAssertNil(s.server(kavita.id))
        XCTAssertEqual(s.favorites(profile: p).map(\.series.ref), [other])
        XCTAssertNil(s.progress(ref, profile: p))
        XCTAssertEqual(s.readerSettings(for: ref, profile: p), .default)
    }

    func testCannotRemoveLastProfile() {
        var s = AppState.initial()
        XCTAssertFalse(s.removeProfile(s.profiles[0].id))
        let b = s.addProfile(name: "B").id
        s.setActiveProfile(b)
        XCTAssertTrue(s.removeProfile(b))
        XCTAssertEqual(s.activeProfileID, s.profiles[0].id)
    }

    func testReaderSettingsOverridePerSeries() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let a = SeriesRef(serverID: kavita.id, seriesID: "1")
        let b = SeriesRef(serverID: kavita.id, seriesID: "2")
        s.setReaderSettings(.webtoonDefault, for: a, profile: p)
        XCTAssertEqual(s.readerSettings(for: a, profile: p).mode, .webtoon)
        XCTAssertEqual(s.readerSettings(for: b, profile: p).mode, .paged)
        var def = ReaderSettings.default
        def.direction = .leftToRight
        s.setDefaultReaderSettings(def, profile: p)
        XCTAssertEqual(s.readerSettings(for: b, profile: p).direction, .leftToRight)
    }

    func testStateStoreRoundTrip() {
        let backing = InMemoryKeyValueStore()
        let store = StateStore(backing: backing)
        XCTAssertEqual(store.load().profiles.count, 1) // empty -> initial
        var s = AppState.initial()
        s.addServer(kavita)
        s.addProfile(name: "B")
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testSecretStoreIsPerProfile() {
        let secrets = InMemorySecretStore()
        let a = UUID(), b = UUID()
        secrets.setCredential(ServerCredential(apiKey: "aaa"), profile: a, server: kavita.id)
        secrets.setCredential(ServerCredential(apiKey: "bbb"), profile: b, server: kavita.id)
        XCTAssertEqual(secrets.credential(profile: a, server: kavita.id)?.apiKey, "aaa")
        XCTAssertEqual(secrets.credential(profile: b, server: kavita.id)?.apiKey, "bbb")
        secrets.removeCredentials(server: kavita.id, profiles: [a, b])
        XCTAssertNil(secrets.credential(profile: a, server: kavita.id))
    }
}
