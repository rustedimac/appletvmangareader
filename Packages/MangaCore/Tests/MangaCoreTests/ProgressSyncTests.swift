import XCTest
@testable import MangaCore

final class ProgressSyncTests: XCTestCase {
    let server = UUID()
    var ref: SeriesRef { SeriesRef(serverID: server, seriesID: "7") }
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func chapter(_ n: Int, read: Bool = false, page: Int = 0, at: Date? = nil) -> Chapter {
        Chapter(id: "\(n)", seriesRef: ref, title: "Chapter \(n)", number: Double(n), pageCount: 20,
                lastPageRead: page, isRead: read, lastReadAt: at)
    }

    func detail(_ chapters: [Chapter]) -> SeriesDetail {
        SeriesDetail(summary: SeriesSummary(ref: ref, title: "T", coverURL: nil), synopsis: nil,
                     authors: [], genres: [], status: nil, chapters: chapters)
    }

    // MARK: Reconcile

    func testLocalChangeNewerThanServerWinsAndIsPushed() {
        let server = detail([chapter(1, read: true, at: t0), chapter(2, page: 3, at: t0)])
        let local = PendingProgress(chapterID: "2", page: 9, completed: false, at: t0.addingTimeInterval(60))
        let r = ProgressSync.reconcile(server, pending: [local])
        XCTAssertEqual(r.push, [local])
        XCTAssertEqual(r.dropped, [])
        XCTAssertEqual(r.detail.chapters[1].lastPageRead, 9)
        XCTAssertEqual(r.detail.chapters[1].lastReadAt, local.at)
        XCTAssertEqual(r.detail.continueChapter?.id, "2")
    }

    func testServerNewerThanLocalWinsAndLocalIsDropped() {
        // Read further on the Kavita web reader after this Apple TV went offline.
        let server = detail([chapter(1, read: true, at: t0.addingTimeInterval(500)), chapter(2, page: 12, at: t0.addingTimeInterval(600))])
        let stale = PendingProgress(chapterID: "2", page: 4, completed: false, at: t0)
        let r = ProgressSync.reconcile(server, pending: [stale])
        XCTAssertEqual(r.push, [])
        XCTAssertEqual(r.dropped, [stale])
        XCTAssertEqual(r.detail, server)
    }

    func testServerWithoutDateLosesToQueuedChange() {
        let server = detail([chapter(1), chapter(2)])
        let local = PendingProgress(chapterID: "1", page: 19, completed: true, at: t0)
        let r = ProgressSync.reconcile(server, pending: [local])
        XCTAssertEqual(r.push, [local])
        XCTAssertTrue(r.detail.chapters[0].isRead)
        XCTAssertEqual(r.detail.continueChapter?.id, "2")
    }

    func testPerChapterDecisionsAndMissingChapters() {
        let server = detail([chapter(1, read: true, at: t0.addingTimeInterval(100)), chapter(2)])
        let older = PendingProgress(chapterID: "1", page: 2, completed: false, at: t0)
        let newer = PendingProgress(chapterID: "2", page: 5, completed: false, at: t0.addingTimeInterval(200))
        let gone = PendingProgress(chapterID: "99", page: 1, completed: false, at: t0)
        let r = ProgressSync.reconcile(server, pending: [newer, gone, older])
        XCTAssertEqual(r.push, [newer])
        XCTAssertEqual(Set(r.dropped), [older, gone])
        XCTAssertTrue(r.detail.chapters[0].isRead, "server's newer read state kept")
    }

    func testRereadingAFinishedChapterMovesItBackToInProgress() {
        let server = detail([chapter(1, read: true, at: t0)])
        let local = PendingProgress(chapterID: "1", page: 3, completed: false, at: t0.addingTimeInterval(10))
        let r = ProgressSync.reconcile(server, pending: [local])
        XCTAssertFalse(r.detail.chapters[0].isRead)
        XCTAssertEqual(r.detail.chapters[0].lastPageRead, 3)
    }

    // MARK: Queue in AppState

    func testQueueKeepsNewestPerChapterAndClears() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        s.queuePending(PendingProgress(chapterID: "1", page: 1, completed: false, at: t0), for: ref, profile: p)
        s.queuePending(PendingProgress(chapterID: "1", page: 5, completed: false, at: t0.addingTimeInterval(5)), for: ref, profile: p)
        s.queuePending(PendingProgress(chapterID: "2", page: 0, completed: false, at: t0.addingTimeInterval(9)), for: ref, profile: p)
        XCTAssertEqual(s.pending(ref, profile: p).map(\.page), [5, 0])
        XCTAssertEqual(s.seriesWithPending(server: server, profile: p), [ref])
        XCTAssertEqual(s.seriesWithPending(server: UUID(), profile: p), [])

        // A push made at t0+3 doesn't clear a change made later.
        s.clearPending(ref, chapterIDs: ["1"], through: t0.addingTimeInterval(3), profile: p)
        XCTAssertEqual(s.pending(ref, profile: p).count, 2)
        s.clearPending(ref, chapterIDs: ["1", "2"], through: t0.addingTimeInterval(9), profile: p)
        XCTAssertEqual(s.pending(ref, profile: p), [])
        XCTAssertEqual(s.seriesWithPending(server: server, profile: p), [])
    }

    func testQueueIsCapped() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        for i in 0..<(AppState.maxPendingPerSeries + 5) {
            s.queuePending(PendingProgress(chapterID: "\(i)", page: 0, completed: true, at: t0.addingTimeInterval(Double(i))),
                           for: ref, profile: p)
        }
        let pending = s.pending(ref, profile: p)
        XCTAssertEqual(pending.count, AppState.maxPendingPerSeries)
        XCTAssertEqual(pending.last?.chapterID, "\(AppState.maxPendingPerSeries + 4)")
    }

    func testQueueIsPerProfile() {
        var s = AppState.initial()
        let me = s.profiles[0].id
        let kid = s.addProfile(name: "Kid").id
        s.queuePending(PendingProgress(chapterID: "1", page: 1, completed: false, at: t0), for: ref, profile: me)
        XCTAssertEqual(s.pending(ref, profile: kid), [])
    }

    // MARK: Local Continue Reading

    func testLocalContinueReadingNewestFirstWithoutSecrets() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let other = SeriesRef(serverID: server, seriesID: "8")
        let cover = URL(string: "http://kavita.local/api/Image/series-cover?apiKey=SECRET&seriesId=7")!
        s.recordProgress(ref, chapterID: "1", page: 2, completed: false, profile: p, now: t0,
                         series: SeriesSummary(ref: ref, title: "Seven", coverURL: cover))
        s.recordProgress(other, chapterID: "3", page: 0, completed: true, profile: p, now: t0.addingTimeInterval(9),
                         series: SeriesSummary(ref: other, title: "Eight", coverURL: nil))
        // Progress with no summary (recorded by an older build) is skipped.
        s.recordProgress(SeriesRef(serverID: server, seriesID: "9"), chapterID: "1", page: 1, completed: false, profile: p)
        s.recordProgress(SeriesRef(serverID: UUID(), seriesID: "1"), chapterID: "1", page: 1, completed: false, profile: p,
                         series: SeriesSummary(ref: SeriesRef(serverID: UUID(), seriesID: "1"), title: "Elsewhere", coverURL: nil))

        let row = s.localContinueReading(server: server, profile: p)
        XCTAssertEqual(row.map(\.title), ["Eight", "Seven"])
        XCTAssertEqual(row[1].coverURL?.absoluteString, "http://kavita.local/api/Image/series-cover?seriesId=7")
        let saved = String(decoding: try! JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertFalse(saved.contains("SECRET"), "API keys never reach AppState")
    }

    func testOldSavedProgressStillDecodes() throws {
        let json = #"{"chapterID":"5","page":3,"updatedAt":700000000,"readChapterIDs":["4"]}"#
        let p = try JSONDecoder().decode(SeriesProgress.self, from: Data(json.utf8))
        XCTAssertEqual(p.chapterID, "5")
        XCTAssertEqual(p.readChapterIDs, ["4"])
        XCTAssertNil(p.series)
        XCTAssertEqual(p.pending, [])
        // Empty fields aren't written back.
        let encoded = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(encoded.contains("pending"))
        XCTAssertFalse(encoded.contains("series"))
    }

    func testHomeShowsLocalContinueReadingWhenNotSyncing() async {
        let demo = SampleLibraryServer(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "https://demo.invalid")!),
                                       seriesCount: 10, latency: .zero)
        let mine = SeriesSummary(ref: SeriesRef(serverID: demo.config.id, seriesID: "3"), title: "Mine", coverURL: nil)
        let local = await HomeLoader.load(HomeSource(server: demo, includeContinueReading: false, localContinueReading: [mine]))
        XCTAssertEqual(local.rows.first?.feed, .continueReading)
        XCTAssertEqual(local.rows.first?.series, [mine])
        // A syncing profile uses the server's row, not the local one.
        let synced = await HomeLoader.load(HomeSource(server: demo, includeContinueReading: true, localContinueReading: [mine]))
        XCTAssertFalse(synced.rows.contains { $0.feed == .continueReading }, "nothing read on the server yet")
    }

    // MARK: Continue point

    func testContinueChapterFollowsKavitaRules() {
        // Most recently read unfinished chapter wins.
        let twoStarted = detail([chapter(1, page: 4, at: t0.addingTimeInterval(50)), chapter(2, read: true), chapter(3, page: 2, at: t0)])
        XCTAssertEqual(twoStarted.continueChapter?.id, "1")
        // Without dates, the later one in reading order.
        let undated = detail([chapter(1, page: 4), chapter(2), chapter(3, page: 2)])
        XCTAssertEqual(undated.continueChapter?.id, "3")
        // Nothing in progress: the first unread after the last read, even
        // if an earlier chapter was skipped.
        let skipped = detail([chapter(1, read: true), chapter(2), chapter(3, read: true), chapter(4)])
        XCTAssertEqual(skipped.continueChapter?.id, "4")
        // Last chapter read but an earlier one wasn't: that one.
        let lastRead = detail([chapter(1), chapter(2, read: true)])
        XCTAssertEqual(lastRead.continueChapter?.id, "1")
        XCTAssertEqual(detail([chapter(1), chapter(2)]).continueChapter?.id, "1")
        XCTAssertEqual(detail([chapter(1, read: true), chapter(2, read: true)]).continueChapter?.id, "1")
    }

    // MARK: Server form

    func testKavitaPasswordSignInDraft() {
        var d = ServerDraft(kind: .kavita, address: "kavita.local", kavitaMethod: .password)
        XCTAssertEqual(d.validationMessage, "Enter your Kavita username.")
        d.username = "john"
        XCTAssertEqual(d.validationMessage, "Enter your Kavita password.")
        d.password = "pw"
        XCTAssertTrue(d.isValid)
        XCTAssertTrue(d.needsKavitaSignIn)
        XCTAssertNil(d.credential, "a password is never saved; the app signs in instead")

        // Pasting an OPDS URL switches to the key.
        d.address = "http://kavita.local/api/opds/abc"
        XCTAssertFalse(d.needsKavitaSignIn)
        XCTAssertTrue(d.absorbOPDS())
        XCTAssertEqual(d.kavitaMethod, .apiKey)
        XCTAssertEqual(d.credential?.apiKey, "abc")
    }

    func testEditingAPasswordLoginKeepsIt() {
        let config = ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://kavita.local")!)
        let saved = ServerCredential(apiKey: "app-key", username: "john")
        var d = ServerDraft(editing: config, credential: saved, syncProgress: true)
        XCTAssertEqual(d.kavitaMethod, .password)
        XCTAssertEqual(d.username, "john")
        XCTAssertEqual(d.password, "")
        XCTAssertEqual(d.apiKey, "", "the app's key isn't shown")
        XCTAssertTrue(d.keepsExistingLogin)
        XCTAssertTrue(d.isValid)
        XCTAssertFalse(d.needsKavitaSignIn)
        XCTAssertEqual(d.credential, saved)

        // Someone else: needs their password.
        d.username = "kid"
        XCTAssertFalse(d.isValid)
        d.password = "pw"
        XCTAssertTrue(d.needsKavitaSignIn)

        // A pasted key keeps showing as a key, with its owner.
        let pasted = ServerCredential(apiKey: "opds-key")
        let k = ServerDraft(editing: config, credential: pasted, syncProgress: true)
        XCTAssertEqual(k.kavitaMethod, .apiKey)
        XCTAssertEqual(k.apiKey, "opds-key")
        XCTAssertEqual(k.credential, pasted)

        // No login yet: offers username and password.
        XCTAssertEqual(ServerDraft(editing: config, credential: nil, syncProgress: true).kavitaMethod, .password)
    }

    func testSuwayomiDraftKeepsLoginModeOnlyWhenUnchanged() {
        let config = ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://s.local")!)
        let saved = ServerCredential(username: "john", password: "pw", suwayomiLogin: .token)
        var d = ServerDraft(editing: config, credential: saved, syncProgress: false)
        XCTAssertEqual(d.credential, saved)
        d.password = "new"
        XCTAssertNil(d.credential?.suwayomiLogin, "detected again on save")
    }
}
