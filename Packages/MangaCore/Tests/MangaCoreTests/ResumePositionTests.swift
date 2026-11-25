import XCTest
@testable import MangaCore

final class ResumePositionTests: XCTestCase {
    let ref = SeriesRef(serverID: UUID(), seriesID: "1")

    func chapter(_ id: String, lastPageRead: Int = 0, isRead: Bool = false, pages: Int = 20) -> Chapter {
        Chapter(id: id, seriesRef: ref, title: id, number: 1, pageCount: pages, lastPageRead: lastPageRead, isRead: isRead)
    }

    func local(_ chapterID: String, page: Int, read: Set<String> = [], at: TimeInterval = 100) -> SeriesProgress {
        SeriesProgress(chapterID: chapterID, page: page, updatedAt: Date(timeIntervalSince1970: at), readChapterIDs: read)
    }

    func testServerProgressWhenNothingLocal() {
        XCTAssertEqual(ResumePosition.startPage(for: chapter("a", lastPageRead: 7), local: nil), 7)
        XCTAssertEqual(ResumePosition.startPage(for: chapter("a", lastPageRead: 19, isRead: true), local: nil), 0)
    }

    func testLocalPageWinsForTheSameChapter() {
        // The server list was fetched before this page was read (or the push
        // hasn't landed yet): the saved local page is the exact one.
        let c = chapter("a", lastPageRead: 3)
        XCTAssertEqual(ResumePosition.startPage(for: c, local: local("a", page: 12)), 12)
    }

    func testLocalProgressForAnotherChapterIsIgnored() {
        let c = chapter("a", lastPageRead: 3)
        XCTAssertEqual(ResumePosition.startPage(for: c, local: local("b", page: 12)), 3)
    }

    func testNewerServerProgressWins() {
        let c = chapter("a", lastPageRead: 15)
        let old = local("a", page: 2, at: 100)
        XCTAssertEqual(ResumePosition.startPage(for: c, local: old, serverReadAt: Date(timeIntervalSince1970: 200)), 15)
        XCTAssertEqual(ResumePosition.startPage(for: c, local: old, serverReadAt: Date(timeIntervalSince1970: 50)), 2)
    }

    func testFinishedChapterOpensAtTheStart() {
        let c = chapter("a", lastPageRead: 19, isRead: true)
        XCTAssertEqual(ResumePosition.startPage(for: c, local: local("a", page: 19, read: ["a"])), 0)
        // Read before, now being read again partway: resume there.
        XCTAssertEqual(ResumePosition.startPage(for: c, local: local("a", page: 6, read: ["a"])), 6)
        // Finished locally even though the server doesn't know yet.
        XCTAssertEqual(ResumePosition.startPage(for: chapter("a"), local: local("a", page: 19, read: ["a"])), 0)
    }

    func testSessionPositionWinsOverEverything() {
        let c = chapter("a", lastPageRead: 19, isRead: true)
        XCTAssertEqual(ResumePosition.startPage(for: c, sessionPage: 8, local: local("a", page: 2)), 8)
    }

    func testMarkedUnreadIgnoresTheServersPage() {
        let c = chapter("a", lastPageRead: 9)
        var p = local("b", page: 3)
        p.unreadChapterIDs = ["a"]
        XCTAssertEqual(ResumePosition.startPage(for: c, local: p), 0)
        var whole = local("", page: 0)
        whole.ignoresServerProgress = true
        XCTAssertEqual(ResumePosition.startPage(for: c, local: whole), 0)
    }

    func testNeverNegative() {
        XCTAssertEqual(ResumePosition.startPage(for: chapter("a", lastPageRead: -1), local: nil), 0)
        XCTAssertEqual(ResumePosition.startPage(for: chapter("a"), local: local("a", page: -5)), 0)
    }

    func testPreviousChapterOpensOnItsLastPage() {
        // `ReaderSession.previousChapter()` opens with startPage Int.max;
        // the navigator lands on the last spread.
        var settings = ReaderSettings.default
        settings.layout = .single
        let single = ReaderNavigator(pageCount: 12, settings: settings, startPage: Int.max)
        XCTAssertEqual(single.currentPage, 11)
        let double = ReaderNavigator(pageCount: 12, settings: .default, startPage: Int.max)
        XCTAssertTrue(double.visiblePages.contains(11))
        XCTAssertTrue(double.isChapterComplete)
    }
}
