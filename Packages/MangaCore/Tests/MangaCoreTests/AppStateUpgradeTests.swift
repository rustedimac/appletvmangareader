import XCTest
@testable import MangaCore

/// Saved `AppState` JSON exactly as each past build wrote it (JSONEncoder,
/// `.sortedKeys`, dates as seconds since 2001). An app update must load
/// every one of these without losing a profile, favorite or page.
///
/// These are the early, small shapes. Newer snapshots are files in
/// `Fixtures/SavedData`, checked field by field by `SavedDataUpgradeTests`:
/// when a PR changes the shape of anything `AppState` stores, add a new file
/// there (see that test and docs/UPGRADE_SAFETY.md).
/// Titles are fictional and hosts are generic.
enum AppStateFixtures {
    static let meID = "0E5B8C3A-1111-4A7B-9C3D-000000000001"
    static let kidID = "0E5B8C3A-2222-4A7B-9C3D-000000000002"
    static let kavitaID = "5A1D2C3B-AAAA-4E5F-8A9B-00000000000A"
    static let suwayomiID = "5A1D2C3B-BBBB-4E5F-8A9B-00000000000B"

    /// Foundation through the reader menu and webtoon reader (#1 to #10).
    static let v1Foundation = #"""
    {"activeProfileID":"0E5B8C3A-2222-4A7B-9C3D-000000000002","profileData":{"0E5B8C3A-1111-4A7B-9C3D-000000000001":{"defaultReaderSettings":{"background":"black","direction":"rightToLeft","firstPageAlone":true,"layout":"double","mode":"paged","shiftPairing":false,"webtoonScrollStep":0.75,"webtoonWidth":0.6},"favorites":[{"addedAt":785000000,"series":{"coverURL":"http:\/\/kavita.local:5000\/api\/image\/series-cover?seriesId=12","libraryID":"1","ref":{"serverID":"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A","seriesID":"12"},"title":"Lantern Harbor","unreadCount":3}}],"progress":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A|12":{"chapterID":"104","page":17,"readChapterIDs":["101","102","103"],"updatedAt":785000100.5}},"readerOverrides":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A|12":{"background":"gray","direction":"leftToRight","firstPageAlone":false,"layout":"single","mode":"webtoon","shiftPairing":true,"webtoonScrollStep":0.5,"webtoonWidth":0.8}},"serverSettings":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A":{"syncProgressToServer":true},"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B":{"syncProgressToServer":true}}},"0E5B8C3A-2222-4A7B-9C3D-000000000002":{"defaultReaderSettings":{"background":"white","direction":"leftToRight","firstPageAlone":true,"layout":"double","mode":"paged","shiftPairing":false,"webtoonScrollStep":0.75,"webtoonWidth":0.6},"favorites":[],"progress":{"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B|7":{"chapterID":"70","page":4,"readChapterIDs":[],"updatedAt":785000200}},"readerOverrides":{},"serverSettings":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A":{"syncProgressToServer":true},"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B":{"syncProgressToServer":false}}}},"profiles":[{"colorIndex":0,"id":"0E5B8C3A-1111-4A7B-9C3D-000000000001","name":"Me","symbol":"person.fill"},{"colorIndex":1,"id":"0E5B8C3A-2222-4A7B-9C3D-000000000002","name":"Kid","symbol":"star.fill"}],"servers":[{"baseURL":"http:\/\/kavita.local:5000","id":"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A","kind":"kavita","name":"Kavita"},{"baseURL":"http:\/\/suwayomi.local:4567","id":"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B","kind":"suwayomi","name":"Suwayomi"}],"version":1}
    """#

    /// Adds the library/category picker (#12): `selectedCategoryIDs` on
    /// server settings and `categoryIDs` on saved series.
    static let v1LibrarySelection = #"""
    {"activeProfileID":"0E5B8C3A-2222-4A7B-9C3D-000000000002","profileData":{"0E5B8C3A-1111-4A7B-9C3D-000000000001":{"defaultReaderSettings":{"background":"black","direction":"rightToLeft","firstPageAlone":true,"layout":"double","mode":"paged","shiftPairing":false,"webtoonScrollStep":0.75,"webtoonWidth":0.6},"favorites":[{"addedAt":785000000,"series":{"coverURL":"http:\/\/kavita.local:5000\/api\/image\/series-cover?seriesId=12","libraryID":"1","ref":{"serverID":"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A","seriesID":"12"},"title":"Lantern Harbor","unreadCount":3}},{"addedAt":785000050,"series":{"categoryIDs":["0","2"],"ref":{"serverID":"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B","seriesID":"7"},"title":"Paper Comet"}}],"progress":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A|12":{"chapterID":"104","page":17,"readChapterIDs":["101","102","103"],"updatedAt":785000100.5}},"readerOverrides":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A|12":{"background":"gray","direction":"leftToRight","firstPageAlone":false,"layout":"single","mode":"webtoon","shiftPairing":true,"webtoonScrollStep":0.5,"webtoonWidth":0.8}},"serverSettings":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A":{"selectedCategoryIDs":["1","3"],"syncProgressToServer":true},"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B":{"syncProgressToServer":true}}},"0E5B8C3A-2222-4A7B-9C3D-000000000002":{"defaultReaderSettings":{"background":"white","direction":"leftToRight","firstPageAlone":true,"layout":"double","mode":"paged","shiftPairing":false,"webtoonScrollStep":0.75,"webtoonWidth":0.6},"favorites":[],"progress":{"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B|7":{"chapterID":"70","page":4,"readChapterIDs":[],"updatedAt":785000200}},"readerOverrides":{},"serverSettings":{"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A":{"syncProgressToServer":true},"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B":{"selectedCategoryIDs":[],"syncProgressToServer":false}}}},"profiles":[{"colorIndex":0,"id":"0E5B8C3A-1111-4A7B-9C3D-000000000001","name":"Me","symbol":"person.fill"},{"colorIndex":1,"id":"0E5B8C3A-2222-4A7B-9C3D-000000000002","name":"Kid","symbol":"star.fill"}],"servers":[{"baseURL":"http:\/\/kavita.local:5000","id":"5A1D2C3B-AAAA-4E5F-8A9B-00000000000A","kind":"kavita","name":"Kavita"},{"baseURL":"http:\/\/suwayomi.local:4567","id":"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B","kind":"suwayomi","name":"Suwayomi"}],"version":1}
    """#

    /// Adds mark unread (#11): `unreadChapterIDs` and
    /// `ignoresServerProgress` on progress, written only when set.
    static let v1MarkUnread = v1LibrarySelection.replacingOccurrences(
        of: #""chapterID":"70","page":4,"readChapterIDs":[],"updatedAt":785000200}"#,
        with: #""chapterID":"70","page":4,"readChapterIDs":[],"unreadChapterIDs":["69"],"updatedAt":785000200},"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B|8":{"chapterID":"","ignoresServerProgress":true,"page":0,"readChapterIDs":[],"updatedAt":785000300}"#)

    /// Adds read progress sync (#15): `series` (for the local Continue
    /// Reading row) and `pending` (changes the server hasn't confirmed) on
    /// progress, written only when set.
    static let v1ReadSync = v1MarkUnread.replacingOccurrences(
        of: #""chapterID":"70","page":4,"readChapterIDs":[],"unreadChapterIDs":["69"],"updatedAt":785000200}"#,
        with: #""chapterID":"70","page":4,"pending":[{"at":785000200,"chapterID":"70","completed":false,"page":4}],"readChapterIDs":[],"series":{"categoryIDs":["0","2"],"ref":{"serverID":"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B","seriesID":"7"},"title":"Paper Comet"},"unreadChapterIDs":["69"],"updatedAt":785000200}"#)

    /// Every shape a shipped or merged build has written, oldest first.
    static let all: [(name: String, json: String)] = [
        ("v1 foundation (#1-#10)", v1Foundation),
        ("v1 library selection (#12)", v1LibrarySelection),
        ("v1 mark unread (#11)", v1MarkUnread),
        ("v1 read sync (#15)", v1ReadSync),
    ]
}

final class AppStateUpgradeTests: XCTestCase {
    typealias F = AppStateFixtures
    let me = UUID(uuidString: F.meID)!
    let kid = UUID(uuidString: F.kidID)!
    let kavita = UUID(uuidString: F.kavitaID)!
    let suwayomi = UUID(uuidString: F.suwayomiID)!

    private func makeStore(with json: String) -> (StateStore, InMemoryKeyValueStore) {
        let backing = InMemoryKeyValueStore()
        backing.set(Data(json.utf8), forKey: StateStore.key)
        return (StateStore(backing: backing), backing)
    }

    func testEveryFixtureKeepsEverything() throws {
        for (name, json) in F.all {
            let (store, backing) = makeStore(with: json)
            let s = store.load()
            XCTAssertEqual(store.lastLoad, .decoded, name)
            XCTAssertNil(backing.data(forKey: StateStore.backupKey), name)

            // Profiles and the active one.
            XCTAssertEqual(s.profiles.map(\.name), ["Me", "Kid"], name)
            XCTAssertEqual(s.profiles.map(\.symbol), ["person.fill", "star.fill"], name)
            XCTAssertEqual(s.activeProfile?.id, kid, name)

            // Servers.
            XCTAssertEqual(s.servers.map(\.kind), [.kavita, .suwayomi], name)
            XCTAssertEqual(s.server(kavita)?.baseURL.absoluteString, "http://kavita.local:5000", name)
            XCTAssertEqual(s.server(kavita)?.alternateURLs, [], name)

            // Reading progress, to the page.
            let lantern = SeriesRef(serverID: kavita, seriesID: "12")
            let p = try XCTUnwrap(s.progress(lantern, profile: me), name)
            XCTAssertEqual(p.chapterID, "104", name)
            XCTAssertEqual(p.page, 17, name)
            XCTAssertEqual(p.readChapterIDs, ["101", "102", "103"], name)
            XCTAssertEqual(p.updatedAt, Date(timeIntervalSinceReferenceDate: 785000100.5), name)
            let comet = SeriesRef(serverID: suwayomi, seriesID: "7")
            XCTAssertEqual(s.progress(comet, profile: kid)?.page, 4, name)
            XCTAssertNil(s.progress(comet, profile: me), "progress stays per profile: \(name)")

            // Favorites.
            let favorites = s.favorites(profile: me)
            XCTAssertTrue(favorites.contains { $0.series.title == "Lantern Harbor" && $0.series.libraryID == "1" }, name)
            XCTAssertTrue(s.favorites(profile: kid).isEmpty, name)

            // Sync choices: Kid reads the shared Suwayomi server locally.
            XCTAssertTrue(s.serverSettings(profile: me, server: suwayomi).syncProgressToServer, name)
            XCTAssertFalse(s.serverSettings(profile: kid, server: suwayomi).syncProgressToServer, name)

            // Reader settings: profile defaults and per-series overrides.
            XCTAssertEqual(s.readerSettings(for: comet, profile: kid).background, .white, name)
            let override = s.readerSettings(for: lantern, profile: me)
            XCTAssertEqual(override.mode, .webtoon, name)
            XCTAssertEqual(override.direction, .leftToRight, name)
            XCTAssertEqual(override.webtoonWidth, 0.8, name)
            // Saved as First Page Alone off + Shift by one: read back as one
            // First Page Alone value with the same layout.
            XCTAssertTrue(override.firstPageAlone, name)
            XCTAssertFalse(override.shiftPairing, name)
        }
    }

    func testFieldsAddedLaterGetDefaults() throws {
        // Saved before #12: every library is selected.
        let old = AppStateFixtures.v1Foundation
        let s = StateStore(backing: { let b = InMemoryKeyValueStore(); b.set(Data(old.utf8), forKey: StateStore.key); return b }()).load()
        XCTAssertNil(s.selectedCategories(profile: me, server: kavita))
        XCTAssertNil(s.favorites(profile: me).first?.series.categoryIDs)

        // Saved by #12: the selection is kept, including "none".
        let (store, _) = makeStore(with: F.v1LibrarySelection)
        let n = store.load()
        XCTAssertEqual(n.selectedCategories(profile: me, server: kavita), ["1", "3"])
        XCTAssertEqual(n.selectedCategories(profile: kid, server: suwayomi), [])
        XCTAssertEqual(n.favorites(profile: me).first?.series.categoryIDs, ["0", "2"])
    }

    func testMarkUnreadFieldsSurvive() throws {
        XCTAssertNotEqual(F.v1MarkUnread, F.v1LibrarySelection)
        let (store, _) = makeStore(with: F.v1MarkUnread)
        let s = store.load()
        XCTAssertEqual(store.lastLoad, .decoded)
        XCTAssertEqual(s.progress(SeriesRef(serverID: suwayomi, seriesID: "7"), profile: kid)?.unreadChapterIDs, ["69"])
        XCTAssertEqual(s.progress(SeriesRef(serverID: suwayomi, seriesID: "8"), profile: kid)?.ignoresServerProgress, true)
        // Older shapes default to nothing marked.
        let old = makeStore(with: F.v1Foundation).0.load()
        XCTAssertEqual(old.progress(SeriesRef(serverID: suwayomi, seriesID: "7"), profile: kid)?.unreadChapterIDs, [])
    }

    func testReadSyncFieldsSurvive() throws {
        XCTAssertNotEqual(F.v1ReadSync, F.v1MarkUnread)
        let comet = SeriesRef(serverID: suwayomi, seriesID: "7")
        let (store, _) = makeStore(with: F.v1ReadSync)
        let s = store.load()
        XCTAssertEqual(store.lastLoad, .decoded)
        let p = try XCTUnwrap(s.progress(comet, profile: kid))
        XCTAssertEqual(p.pending, [PendingProgress(chapterID: "70", page: 4, completed: false,
                                                   at: Date(timeIntervalSinceReferenceDate: 785000200))])
        XCTAssertEqual(p.series?.title, "Paper Comet")
        XCTAssertEqual(p.unreadChapterIDs, ["69"])
        // State saved before #15 has nothing queued and no saved series.
        let old = makeStore(with: F.v1MarkUnread).0.load()
        let o = try XCTUnwrap(old.progress(comet, profile: kid))
        XCTAssertTrue(o.pending.isEmpty)
        XCTAssertNil(o.series)
    }

    func testEveryFixtureSurvivesSaveAndReload() {
        for (name, json) in F.all {
            let (store, backing) = makeStore(with: json)
            let loaded = store.load()
            store.save(loaded)
            let again = StateStore(backing: backing)
            XCTAssertEqual(again.load(), loaded, name)
            XCTAssertEqual(again.lastLoad, .decoded, name)
        }
    }

    func testCurrentStateRoundTripsWithEveryField() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let server = ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://kavita.local")!)
        s.addServer(server)
        s.addProfile(name: "B", symbol: "star.fill")
        let ref = SeriesRef(serverID: server.id, seriesID: "1")
        s.setFavorite(SeriesSummary(ref: ref, title: "A", coverURL: URL(string: "http://kavita.local/c.png"),
                                    unreadCount: 2, libraryID: "1", categoryIDs: ["1"]), true, profile: p,
                      now: Date(timeIntervalSinceReferenceDate: 1))
        s.recordProgress(ref, chapterID: "9", page: 3, completed: true, profile: p,
                         now: Date(timeIntervalSinceReferenceDate: 2))
        s.setReaderSettings(.webtoonDefault, for: ref, profile: p)
        s.setSelectedCategories(["1"], profile: p, server: server.id)
        let backing = InMemoryKeyValueStore()
        StateStore(backing: backing).save(s)
        let store = StateStore(backing: backing)
        XCTAssertEqual(store.load(), s)
        XCTAssertEqual(store.lastLoad, .decoded)
    }

    // MARK: Damaged or unexpected data

    func testOneBadEntryCostsOnlyThatEntry() throws {
        // A favorite with a broken ref (e.g. written by a buggy build).
        let damaged = F.v1LibrarySelection.replacingOccurrences(
            of: #"{"categoryIDs":["0","2"],"ref":{"serverID":"5A1D2C3B-BBBB-4E5F-8A9B-00000000000B","seriesID":"7"}"#,
            with: #"{"categoryIDs":["0","2"],"ref":{"serverID":"not-a-uuid","seriesID":"7"}"#)
        XCTAssertNotEqual(damaged, F.v1LibrarySelection)
        let (store, backing) = makeStore(with: damaged)
        let s = store.load()
        XCTAssertEqual(store.lastLoad, .salvaged)
        XCTAssertEqual(s.favorites(profile: me).map(\.series.title), ["Lantern Harbor"])
        XCTAssertEqual(s.progress(SeriesRef(serverID: kavita, seriesID: "12"), profile: me)?.page, 17)
        XCTAssertEqual(s.progress(SeriesRef(serverID: suwayomi, seriesID: "7"), profile: kid)?.page, 4)
        XCTAssertEqual(s.profiles.count, 2)
        XCTAssertEqual(s.servers.count, 2)
        XCTAssertEqual(s.readerSettings(for: SeriesRef(serverID: kavita, seriesID: "12"), profile: me).mode, .webtoon)
        // The original is kept for a later fix.
        XCTAssertEqual(backing.data(forKey: StateStore.backupKey), Data(damaged.utf8))
    }

    func testUnreadableProfileListStillKeepsProgress() throws {
        let damaged = F.v1Foundation.replacingOccurrences(of: #""profiles":["#, with: #""profiles":7,"oldProfiles":["#)
        let (store, _) = makeStore(with: damaged)
        let s = store.load()
        XCTAssertEqual(store.lastLoad, .salvaged)
        XCTAssertEqual(Set(s.profiles.map(\.id)), [me, kid])
        XCTAssertEqual(s.activeProfile?.id, kid)
        XCTAssertEqual(s.progress(SeriesRef(serverID: kavita, seriesID: "12"), profile: me)?.page, 17)
    }

    func testGarbageStartsFreshButIsKept() {
        let garbage = Data("{not json".utf8)
        let backing = InMemoryKeyValueStore()
        backing.set(garbage, forKey: StateStore.key)
        let store = StateStore(backing: backing)
        let s = store.load()
        XCTAssertEqual(store.lastLoad, .unreadable)
        XCTAssertEqual(s.profiles.count, 1)
        XCTAssertEqual(backing.data(forKey: StateStore.backupKey), garbage)

        // Saving the fresh state doesn't touch the backup, and a second bad
        // load doesn't replace the first backup.
        store.save(s)
        backing.set(Data("[]".utf8), forKey: StateStore.key)
        _ = store.load()
        XCTAssertEqual(backing.data(forKey: StateStore.backupKey), garbage)
    }

    func testStateFromANewerBuildStillLoads() throws {
        // Downgrade (e.g. TestFlight to App Store): unknown fields and a
        // higher version are ignored, everything known is kept.
        let newer = F.v1LibrarySelection
            .replacingOccurrences(of: #""version":1"#, with: #""version":99,"somethingNew":{"a":[1,2]}"#)
            .replacingOccurrences(of: #""page":17,"#, with: #""page":17,"futureField":true,"#)
        let (store, _) = makeStore(with: newer)
        let s = store.load()
        XCTAssertEqual(store.lastLoad, .decoded)
        XCTAssertEqual(s.progress(SeriesRef(serverID: kavita, seriesID: "12"), profile: me)?.page, 17)
    }

    func testMigrateLeavesCurrentDataAloneAndStampsVersion() throws {
        let current = Data(F.v1LibrarySelection.utf8)
        XCTAssertEqual(try AppStateUpgrade.migrate(current), current)

        // No version at all is treated as version 1.
        let unversioned = F.v1Foundation.replacingOccurrences(of: #","version":1"#, with: "")
        XCTAssertNotEqual(unversioned, F.v1Foundation)
        let (state, outcome) = try AppStateUpgrade.decode(Data(unversioned.utf8))
        XCTAssertEqual(outcome, .decoded)
        XCTAssertEqual(state.version, AppState.currentVersion)
        XCTAssertEqual(state.profiles.count, 2)
    }

    func testFixturesMatchTheCurrentVersion() {
        // Bumping `AppState.currentVersion` needs a migration step and a
        // fixture of the old version; this fails as a reminder.
        XCTAssertEqual(AppState.currentVersion, 1,
                       "Add an AppStateUpgrade.step and a fixture for the previous version")
    }
}
