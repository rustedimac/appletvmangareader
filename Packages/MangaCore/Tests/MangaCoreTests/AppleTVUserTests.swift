import XCTest
@testable import MangaCore

final class ProfileLaunchTests: XCTestCase {
    func testWithoutAppleTVUsersPickerShowsForSeveralProfiles() {
        var s = AppState.initial()
        XCTAssertFalse(ProfileLaunch.decide(s, perSystemUser: false).showsPicker)
        let kid = s.addProfile(name: "Kid").id
        XCTAssertTrue(ProfileLaunch.decide(s, perSystemUser: false).showsPicker)
        // A remembered profile is ignored when not running per Apple TV user.
        s.pickProfile(kid, remember: true)
        let launch = ProfileLaunch.decide(s, perSystemUser: false)
        XCTAssertTrue(launch.showsPicker)
    }

    func testAppleTVUserNeverSeesPicker() {
        var s = AppState.initial()
        let me = s.profiles[0].id
        XCTAssertEqual(ProfileLaunch.decide(s, perSystemUser: true), ProfileLaunch(profileID: me, showsPicker: false))
        // Older state with several in-app profiles: the last picked opens.
        let kid = s.addProfile(name: "Kid").id
        XCTAssertEqual(ProfileLaunch.decide(s, perSystemUser: true), ProfileLaunch(profileID: me, showsPicker: false))
        s.pickProfile(kid, remember: true)
        s.setActiveProfile(me)
        XCTAssertEqual(ProfileLaunch.decide(s, perSystemUser: true), ProfileLaunch(profileID: kid, showsPicker: false))
    }

    func testRemovingRememberedProfileForgetsIt() {
        var s = AppState.initial()
        let me = s.profiles[0].id
        let kid = s.addProfile(name: "Kid").id
        s.pickProfile(kid, remember: true)
        s.removeProfile(kid)
        XCTAssertNil(s.rememberedProfileID)
        XCTAssertEqual(ProfileLaunch.decide(s, perSystemUser: true), ProfileLaunch(profileID: me, showsPicker: false))
    }

    func testPickingUnknownProfileDoesNothing() {
        var s = AppState.initial()
        s.pickProfile(UUID(), remember: true)
        XCTAssertNil(s.rememberedProfileID)
    }
}

final class SharedServerTests: XCTestCase {
    let kavita = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local")!)
    let suwayomi = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local")!)

    func testAdoptAddsServersWithoutSync() {
        var s = AppState.initial()
        let kid = s.addProfile(name: "Kid").id
        let dir = SharedServerDirectory(servers: [kavita, suwayomi])
        XCTAssertEqual(s.adopt(dir), [])
        XCTAssertEqual(s.servers.map(\.id), [kavita.id, suwayomi.id])
        for profile in [s.profiles[0].id, kid] {
            XCTAssertFalse(s.serverSettings(profile: profile, server: kavita.id).syncProgressToServer)
            XCTAssertFalse(s.serverSettings(profile: profile, server: suwayomi.id).syncProgressToServer)
        }
    }

    func testAdoptAppliesEditsAndRemovals() {
        var s = AppState.initial()
        s.addServer(kavita)
        s.addServer(suwayomi)
        let p = s.profiles[0].id
        s.setFavorite(SeriesSummary(ref: SeriesRef(serverID: suwayomi.id, seriesID: "1"), title: "A", coverURL: nil),
                      true, profile: p)
        var renamed = kavita
        renamed.name = "Home Kavita"
        let dir = SharedServerDirectory(servers: [renamed], removedServerIDs: [suwayomi.id])
        XCTAssertEqual(s.adopt(dir), [suwayomi.id])
        XCTAssertEqual(s.servers, [renamed])
        XCTAssertTrue(s.favorites(profile: p).isEmpty)
        // This user's own sync settings for a server they already had stay.
        XCTAssertTrue(s.serverSettings(profile: p, server: kavita.id).syncProgressToServer)
    }

    func testRecordTracksAddsEditsAndRemovals() {
        var dir = SharedServerDirectory()
        dir.record(before: [], after: [kavita, suwayomi])
        XCTAssertEqual(dir.servers.map(\.id), [kavita.id, suwayomi.id])
        dir.offerCredential(ServerCredential(username: "u"), for: suwayomi.id)
        var moved = kavita
        moved.baseURL = URL(string: "http://kavita.lan")!
        dir.record(before: [kavita, suwayomi], after: [moved])
        XCTAssertEqual(dir.servers, [moved])
        XCTAssertEqual(dir.removedServerIDs, [suwayomi.id])
        XCTAssertNil(dir.credential(for: suwayomi.id))
        // A removed server isn't brought back by a user who still has it.
        dir.upsert([suwayomi])
        XCTAssertEqual(dir.servers, [moved])
    }

    func testTwoUsersConverge() {
        // User A had servers before sharing was on; user B starts empty.
        var a = AppState.initial()
        a.addServer(kavita)
        var b = AppState.initial()
        var dir = SharedServerDirectory()

        // B launches first: nothing to adopt, and nothing is removed from A.
        b.adopt(dir)
        dir.upsert(b.servers)
        // A launches: A's server joins the directory.
        a.adopt(dir)
        dir.upsert(a.servers)
        // B launches again and gets it.
        b.adopt(dir)
        XCTAssertEqual(b.servers, [kavita])

        // B removes it; A drops it on next launch.
        let before = b.servers
        b.removeServer(kavita.id)
        dir.record(before: before, after: b.servers)
        XCTAssertEqual(a.adopt(dir), [kavita.id])
        XCTAssertTrue(a.servers.isEmpty)
    }

    func testCredentialFallback() {
        let shared = InMemorySharedServerStore(SharedServerDirectory(servers: [kavita]))
        let store = SharedFallbackSecretStore(local: InMemorySecretStore(), shared: shared)
        let me = UUID(), kid = UUID()
        store.setCredential(ServerCredential(apiKey: "mine"), profile: me, server: kavita.id)
        // The first login becomes the shared one.
        XCTAssertEqual(shared.load()?.credential(for: kavita.id)?.apiKey, "mine")
        XCTAssertEqual(store.credential(profile: kid, server: kavita.id)?.apiKey, "mine")
        XCTAssertFalse(store.hasOwnCredential(profile: kid, server: kavita.id))
        // A profile's own login wins, and doesn't replace the shared one.
        store.setCredential(ServerCredential(apiKey: "kid"), profile: kid, server: kavita.id)
        XCTAssertEqual(store.credential(profile: kid, server: kavita.id)?.apiKey, "kid")
        XCTAssertEqual(shared.load()?.credential(for: kavita.id)?.apiKey, "mine")
        // Unknown servers don't get shared logins.
        store.setCredential(ServerCredential(apiKey: "x"), profile: me, server: suwayomi.id)
        XCTAssertNil(shared.load()?.credential(for: suwayomi.id))
    }
}
