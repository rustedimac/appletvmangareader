import XCTest
@testable import MangaCore

final class SyncEngineTests: XCTestCase {
    var cloud: InMemoryCloudStore!

    override func setUp() {
        cloud = InMemoryCloudStore()
    }

    /// A syncs a populated state, B joins from a fresh install.
    func pair() async throws -> (SyncTestDevice, SyncTestDevice) {
        let a = SyncTestDevice(cloud: cloud, state: SyncFixtures.populated(), deviceID: "A")
        let b = SyncTestDevice(cloud: cloud, deviceID: "B")
        try await a.sync()
        b.advance(5)
        try await b.sync()
        return (a, b)
    }

    func testJoiningDeviceGetsEverythingAndAdoptsTheProfile() async throws {
        let (a, b) = try await pair()
        XCTAssertEqual(b.state.profiles.map(\.id), a.state.profiles.map(\.id), "B's fresh 'Me' becomes A's 'Me'")
        XCTAssertEqual(b.state.servers, a.state.servers)
        let p = b.profile
        XCTAssertEqual(b.state.favorites(profile: p).map(\.series.title), ["Star Harbor"])
        let ref = SeriesRef(serverID: a.state.servers[0].id, seriesID: "1")
        let progress = try XCTUnwrap(b.state.progress(ref, profile: p))
        XCTAssertEqual(progress.chapterID, "c2")
        XCTAssertEqual(progress.page, 4)
        XCTAssertEqual(progress.readChapterIDs, ["c1"])
        // A second run on either device finds nothing to do.
        let again = try await b.sync()
        XCTAssertEqual(again.uploaded, 0)
        XCTAssertEqual(again.downloaded, 0)
        let againA = try await a.sync()
        XCTAssertEqual(againA.uploaded, 0)
        XCTAssertEqual(againA.downloaded, 0)
    }

    func testFirstDeviceCustomSettingsBeatAJoiningDevicesDefaults() async throws {
        var custom = SyncFixtures.populated()
        var settings = ReaderSettings.default
        settings.mode = .webtoon
        custom.setDefaultReaderSettings(settings, profile: custom.activeProfile!.id)
        let a = SyncTestDevice(cloud: cloud, state: custom, deviceID: "A")
        let b = SyncTestDevice(cloud: cloud, deviceID: "Z") // larger id would win a tie
        try await a.sync()
        try await b.sync()
        XCTAssertEqual(b.state.profileData[b.profile.uuidString]?.defaultReaderSettings.mode, .webtoon)
    }

    func testDeletionPropagates() async throws {
        let (a, b) = try await pair()
        let p = a.profile
        let series = a.state.favorites(profile: p)[0].series
        a.advance()
        a.change { $0.setFavorite(series, false, profile: p) }
        try await a.sync()
        try await b.sync()
        XCTAssertTrue(b.state.favorites(profile: p).isEmpty)
        XCTAssertTrue(cloud.record("favorite/\(p.uuidString)/\(series.ref.storageKey)")?.isDeleted ?? false)
    }

    func testNewestEditWins() async throws {
        let (a, b) = try await pair()
        var pa = a.state.profiles[0]; pa.name = "Alpha"
        var pb = b.state.profiles[0]; pb.name = "Beta"
        a.advance(60)
        a.change { $0.updateProfile(pa) }
        b.advance(120)
        b.change { $0.updateProfile(pb) }
        try await a.sync()
        try await b.sync() // newer edit, merged against A's
        try await a.sync()
        XCTAssertEqual(a.state.profiles[0].name, "Beta")
        XCTAssertEqual(b.state.profiles[0].name, "Beta")
    }

    func testProgressMergesChapterByChapter() async throws {
        let (a, b) = try await pair()
        let p = a.profile
        let ref = SeriesRef(serverID: a.state.servers[0].id, seriesID: "1")
        a.advance(60)
        a.change { $0.recordProgress(ref, chapterID: "c3", page: 30, completed: true, profile: p, now: a.now) }
        b.advance(120)
        b.change { $0.recordProgress(ref, chapterID: "c5", page: 7, completed: false, profile: p, now: b.now) }
        b.change { $0.recordProgress(ref, chapterID: "c4", page: 25, completed: true, profile: p, now: b.now) }
        try await a.sync()
        try await b.sync()
        try await a.sync()
        for device in [a, b] {
            let progress = try XCTUnwrap(device.state.progress(ref, profile: p))
            XCTAssertEqual(progress.readChapterIDs, ["c1", "c3", "c4"])
            XCTAssertEqual(progress.chapterID, "c4", "B's position is newer")
            XCTAssertEqual(progress.page, 25)
        }
    }

    func testMarkingUnreadPropagates() async throws {
        let (a, b) = try await pair()
        let p = a.profile
        let key = SeriesRef(serverID: a.state.servers[0].id, seriesID: "1").storageKey
        a.advance()
        a.change { $0.profileData[p.uuidString]?.progress[key]?.readChapterIDs.remove("c1") }
        try await a.sync()
        try await b.sync()
        XCTAssertEqual(b.state.profileData[p.uuidString]?.progress[key]?.readChapterIDs, [])
        // B still had c1 read, but its mark is older than A's unread.
        try await a.sync()
        XCTAssertEqual(a.state.profileData[p.uuidString]?.progress[key]?.readChapterIDs, [])
    }

    func testMarkUnreadAndSeriesUnreadSync() async throws {
        let (a, b) = try await pair()
        let p = a.profile
        let ref = SeriesRef(serverID: a.state.servers[0].id, seriesID: "1")
        a.advance()
        a.change { $0.markUnread(ref, chapterIDs: ["c1"], profile: p, now: a.now) }
        try await a.sync()
        try await b.sync()
        XCTAssertEqual(b.state.progress(ref, profile: p)?.readChapterIDs, [])
        XCTAssertEqual(b.state.progress(ref, profile: p)?.unreadChapterIDs, ["c1"])

        b.advance(120)
        b.change { $0.markSeriesUnread(ref, profile: p, now: b.now) }
        try await b.sync()
        try await a.sync()
        XCTAssertEqual(a.state.progress(ref, profile: p)?.ignoresServerProgress, true)
        XCTAssertEqual(a.state.progress(ref, profile: p)?.readChapterIDs, [])
    }

    func testOfflineChangesWaitWithTheirTime() async throws {
        let (a, b) = try await pair()
        let p = a.profile
        a.advance(60)
        let changedAt = a.now
        let extra = SyncFixtures.series(a.state.servers[0].id, "2", "Paper Moon Express")
        a.change { $0.setFavorite(extra, true, profile: p, now: changedAt) }
        cloud.saveFailure = .network
        do {
            try await a.sync()
            XCTFail("expected a network error")
        } catch {
            XCTAssertEqual(error as? SyncStoreError, .network)
        }
        let pending = await a.engine.pendingCount
        XCTAssertEqual(pending, 1)

        // Relaunch later, back online: the queued change goes up with its
        // original time.
        cloud.saveFailure = nil
        a.advance(3600)
        a.relaunch()
        let report = try await a.sync()
        XCTAssertEqual(report.uploaded, 1)
        XCTAssertEqual(report.pending, 0)
        let key = "favorite/\(p.uuidString)/\(extra.ref.storageKey)"
        XCTAssertEqual(cloud.record(key)?.modifiedAt, changedAt)
        try await b.sync()
        XCTAssertEqual(b.state.favorites(profile: p).count, 2)
    }

    func testSaveRaceIsMergedWithTheCloudVersion() async throws {
        let (a, _) = try await pair()
        let p = a.profile
        var mine = ReaderSettings.default
        mine.mode = .webtoon
        a.advance(60)
        a.change { $0.setDefaultReaderSettings(mine, profile: p) }

        // Another device saves a newer value between A's fetch and save.
        var theirs = ReaderSettings.default
        theirs.direction = .leftToRight
        let key = "readerDefaults/\(p.uuidString)"
        cloud.beforeSave = { [cloud] in
            cloud!.put(SyncRecord(key: key, kind: .readerDefaults, payload: SyncMapper.encode(theirs),
                                  modifiedAt: a.now.addingTimeInterval(30), deviceID: "C"))
        }
        let report = try await a.sync()
        XCTAssertEqual(report.conflicts, 1)
        XCTAssertEqual(a.state.profileData[p.uuidString]?.defaultReaderSettings, theirs)
        XCTAssertEqual(report.pending, 0)
    }

    func testUnknownKindsAreKeptNotDeleted() async throws {
        let (a, _) = try await pair()
        let future = SyncRecord(key: "bookmark/x/1", kind: SyncKind("bookmark"), payload: Data("{\"page\":3}".utf8),
                                modifiedAt: a.now, deviceID: "phone")
        cloud.put(future)
        try await a.sync()
        a.advance()
        try await a.sync()
        XCTAssertEqual(cloud.record(future.key), future)
    }

    func testRemovedServerAlsoRemovesLoginsOnOtherDevice() async throws {
        let (a, b) = try await pair()
        let server = a.state.servers[0].id
        b.secrets.setCredential(ServerCredential(apiKey: "test-key"), profile: b.profile, server: server)
        a.advance()
        a.change { $0.removeServer(server) }
        try await a.sync()
        try await b.sync()
        XCTAssertTrue(b.state.servers.isEmpty)
        XCTAssertNil(b.secrets.credential(profile: b.profile, server: server))
        XCTAssertTrue(b.state.favorites(profile: b.profile).isEmpty)
    }

    func testJoiningDeviceMergesTheSameServerAndKeepsItsLogin() async throws {
        let a = SyncTestDevice(cloud: cloud, state: SyncFixtures.populated(), deviceID: "A")
        try await a.sync()

        var mine = AppState.initial()
        let own = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://KAVITA.example:5000/")!)
        mine.addServer(own)
        let b = SyncTestDevice(cloud: cloud, state: mine, deviceID: "B")
        b.secrets.setCredential(ServerCredential(apiKey: "b-key"), profile: b.profile, server: own.id)
        try await b.sync()

        let shared = a.state.servers[0].id
        XCTAssertEqual(b.state.servers.map(\.id), [shared])
        XCTAssertEqual(b.state.servers[0].name, "Home Kavita", "the cloud's name wins for a joining device")
        XCTAssertEqual(b.secrets.credential(profile: b.profile, server: shared)?.apiKey, "b-key")
        XCTAssertNil(b.secrets.credential(profile: b.profile, server: own.id))
        XCTAssertEqual(b.state.favorites(profile: b.profile).count, 1)
    }

    func testExpiredTokenRefetchesEverything() async throws {
        let (a, b) = try await pair()
        a.advance()
        var p = a.state.profiles[0]; p.symbol = "star.fill"
        a.change { $0.updateProfile(p) }
        try await a.sync()
        cloud.minimumToken = Int.max
        try await b.sync()
        XCTAssertEqual(b.state.profiles[0].symbol, "star.fill")
    }

    func testDifferentAccountStartsOver() async throws {
        let (a, _) = try await pair()
        cloud.status = .available(userID: "someone-else")
        cloud.wipe()
        let report = try await a.sync()
        XCTAssertGreaterThan(report.uploaded, 0)
        XCTAssertFalse(cloud.all.isEmpty)
    }

    func testBuildsWithoutICloudDoNothing() async throws {
        let device = SyncTestDevice(cloud: cloud, state: SyncFixtures.populated(), deviceID: "A")
        let engine = SyncEngine(store: LocalOnlySyncStore(), persistence: InMemorySyncPersistence())
        let before = device.state
        let report = try await engine.sync(host: device.host)
        XCTAssertEqual(report.status, .notConfigured)
        XCTAssertEqual(device.state, before)
    }

    func testNoAccountDoesNothing() async throws {
        cloud.status = .noAccount
        let device = SyncTestDevice(cloud: cloud, state: SyncFixtures.populated(), deviceID: "A")
        let report = try await device.sync()
        XCTAssertEqual(report.status, .noAccount)
        XCTAssertTrue(cloud.all.isEmpty)
    }

    func testChangesStillUploadAfterTheCloudIsEmptied() async throws {
        let (a, _) = try await pair()
        cloud.wipe()
        // The real store reports a missing zone on fetch; the fake can't, so
        // this covers the "cloud emptied" path: a changed value re-uploads.
        a.advance()
        var p = a.state.profiles[0]; p.colorIndex = 5
        a.change { $0.updateProfile(p) }
        let report = try await a.sync()
        XCTAssertEqual(report.uploaded, 1)
    }
}
