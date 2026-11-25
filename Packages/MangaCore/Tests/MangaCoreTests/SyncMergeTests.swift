import XCTest
@testable import MangaCore

final class SyncMergeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func record(_ value: String?, at: Date, device: String = "A") -> SyncRecord {
        SyncRecord(key: "profile/x", kind: .profile, payload: value.map { Data($0.utf8) }, modifiedAt: at, deviceID: device)
    }

    func testNewestWinsAndTiesAreStable() {
        XCTAssertEqual(SyncMerge.merge(record("a", at: t0), record("b", at: t0 + 1)).payload, Data("b".utf8))
        XCTAssertEqual(SyncMerge.merge(record("a", at: t0 + 1), record("b", at: t0)).payload, Data("a".utf8))
        let x = SyncMerge.merge(record("a", at: t0, device: "A"), record("b", at: t0, device: "B"))
        let y = SyncMerge.merge(record("b", at: t0, device: "B"), record("a", at: t0, device: "A"))
        XCTAssertEqual(x.payload, y.payload, "both devices pick the same winner")
    }

    func testNewerDeletionWins() {
        XCTAssertTrue(SyncMerge.merge(record(nil, at: t0 + 5), record("b", at: t0)).isDeleted)
        XCTAssertFalse(SyncMerge.merge(record(nil, at: t0), record("b", at: t0 + 5)).isDeleted)
    }

    func testProgressMergesMarksAndKeepsNewestPosition() {
        let a = SyncedProgress(chapterID: "c3", page: 1, positionAt: t0 + 10,
                               marks: ["c1": ReadMark(read: true, at: t0), "c2": ReadMark(read: false, at: t0 + 9)])
        let b = SyncedProgress(chapterID: "c2", page: 8, positionAt: t0 + 5,
                               marks: ["c2": ReadMark(read: true, at: t0 + 5), "c4": ReadMark(read: true, at: t0 + 1)])
        let m = SyncMerge.mergeProgress(a, b)
        XCTAssertEqual(m.chapterID, "c3")
        XCTAssertEqual(m.readChapterIDs, ["c1", "c4"], "c2 was marked unread after it was read")
        XCTAssertEqual(SyncMerge.mergeProgress(b, a), m)
    }

    func testStampingFindsNewlyReadAndUnreadChapters() {
        let previous = SyncedProgress(chapterID: "c2", page: 3, positionAt: t0,
                                      marks: ["c1": ReadMark(read: true, at: t0 - 100), "c9": ReadMark(read: false, at: t0 - 50)])
        let local = SyncedProgress(chapterID: "c3", page: 0, positionAt: t0 + 60,
                                   marks: ["c2": ReadMark(read: true, at: t0 + 60), "c3": ReadMark(read: true, at: t0 + 60)])
        let now = t0 + 70
        let s = SyncMerge.stampProgress(local, previous: previous, now: now)
        XCTAssertEqual(s.marks["c1"], ReadMark(read: false, at: now), "c1 was unread here")
        XCTAssertEqual(s.marks["c2"], ReadMark(read: true, at: now))
        XCTAssertEqual(s.marks["c9"], ReadMark(read: false, at: t0 - 50), "old unread mark kept")
        XCTAssertEqual(s.positionAt, t0 + 60)
    }

    func testLocalRecordsStampChangesAndDeletions() {
        let s = SyncFixtures.populated()
        let first = SyncMerge.localRecords(state: s, reference: [:], deviceID: "A", now: t0, joining: true)
        let p = s.activeProfile!.id.uuidString
        XCTAssertEqual(first["profile/\(p)"]?.modifiedAt, .distantPast, "joining: no date of its own")
        XCTAssertEqual(first["favorite/\(p)/\(s.servers[0].id.uuidString)|1"]?.modifiedAt,
                       Date(timeIntervalSince1970: 1_700_000_000), "joining: the favorite's own date")

        var changed = s
        var profile = changed.profiles[0]; profile.name = "Renamed"
        changed.updateProfile(profile)
        changed.setFavorite(s.favorites(profile: s.activeProfile!.id)[0].series, false, profile: s.activeProfile!.id)
        let second = SyncMerge.localRecords(state: changed, reference: first, deviceID: "A", now: t0 + 10, joining: false)
        XCTAssertEqual(second["profile/\(p)"]?.modifiedAt, t0 + 10)
        let fav = second["favorite/\(p)/\(s.servers[0].id.uuidString)|1"]
        XCTAssertEqual(fav?.isDeleted, true)
        XCTAssertEqual(fav?.modifiedAt, t0 + 10)
        XCTAssertEqual(second["server/\(s.servers[0].id.uuidString)"], first["server/\(s.servers[0].id.uuidString)"],
                       "unchanged values keep their record")
    }
}
