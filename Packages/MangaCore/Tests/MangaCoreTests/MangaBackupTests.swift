import XCTest
@testable import MangaCore

final class MangaBackupTests: XCTestCase {
    func testExportIsReadableVersionedJSON() throws {
        let data = MangaBackup.export(state: SyncFixtures.populated(), appVersion: "0.1.0")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["format"] as? String, "mangareader-backup")
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(root["app"] as? String, "0.1.0")
        let records = try XCTUnwrap(root["records"] as? [[String: Any]])
        let favorite = try XCTUnwrap(records.first { $0["kind"] as? String == "favorite" })
        let value = try XCTUnwrap(favorite["value"] as? [String: Any])
        XCTAssertEqual((value["series"] as? [String: Any])?["title"] as? String, "Star Harbor")
    }

    func testParseReturnsTheSameRecords() throws {
        let state = SyncFixtures.populated()
        let records = try MangaBackup.parse(MangaBackup.export(state: state))
        let expected = SyncMapper.payloads(from: state)
        XCTAssertEqual(Set(records.map(\.key)), Set(expected.keys))
        for r in records {
            XCTAssertTrue(SyncMapper.samePayload(r.kind, r.payload, expected[r.key]?.payload), r.key)
        }
    }

    func testRestoreOntoAFreshInstall() throws {
        let source = SyncFixtures.populated()
        let backup = try MangaBackup.parse(MangaBackup.export(state: source))
        var fresh = AppState.initial()
        let patch = MangaBackup.restorePatch(state: fresh, backup: backup)
        let effects = SyncMapper.apply(patch, to: &fresh)

        XCTAssertEqual(fresh.profiles.map(\.id), source.profiles.map(\.id), "'Me' is the same profile")
        XCTAssertEqual(fresh.servers, source.servers)
        let p = fresh.activeProfile!.id
        XCTAssertEqual(fresh.favorites(profile: p).count, 1)
        XCTAssertEqual(fresh.progress(SeriesRef(serverID: source.servers[0].id, seriesID: "1"), profile: p)?.page, 4)
        XCTAssertEqual(effects.appliedCount[.favorite], 1)
        XCTAssertTrue(MangaBackup.summary(effects).contains("1 favorite"))
    }

    func testRestoreMergesAndDeletesNothing() throws {
        let source = SyncFixtures.populated()
        let backup = try MangaBackup.parse(MangaBackup.export(state: source))
        var local = source
        let p = local.activeProfile!.id
        let server = local.servers[0].id
        let ref = SeriesRef(serverID: server, seriesID: "1")
        // Since the backup: another favorite and further progress.
        local.setFavorite(SyncFixtures.series(server, "2", "Paper Moon Express"), true, profile: p)
        local.recordProgress(ref, chapterID: "c3", page: 1, completed: false, profile: p,
                             now: Date(timeIntervalSince1970: 1_750_000_000))
        local.profileData[p.uuidString]?.progress[ref.storageKey]?.readChapterIDs.insert("c2")
        let patch = MangaBackup.restorePatch(state: local, backup: backup)
        SyncMapper.apply(patch, to: &local)
        XCTAssertEqual(local.favorites(profile: p).count, 2)
        XCTAssertEqual(local.progress(ref, profile: p)?.chapterID, "c3", "the furthest position stays")
        XCTAssertEqual(local.progress(ref, profile: p)?.readChapterIDs, ["c1", "c2"])
        XCTAssertEqual(MangaBackup.summary(SyncMapper.apply(MangaBackup.restorePatch(state: local, backup: backup), to: &local)),
                       "Nothing new: everything in the backup was already here.")
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try MangaBackup.parse(Data("{\"hello\":1}".utf8))) {
            XCTAssertEqual($0 as? MangaBackup.BackupError, .notABackup)
        }
        XCTAssertThrowsError(try MangaBackup.parse(Data("not json".utf8)))
        let newer = Data("{\"format\":\"mangareader-backup\",\"version\":99,\"records\":[]}".utf8)
        XCTAssertThrowsError(try MangaBackup.parse(newer)) {
            XCTAssertEqual($0 as? MangaBackup.BackupError, .newerVersion(99))
        }
    }
}
