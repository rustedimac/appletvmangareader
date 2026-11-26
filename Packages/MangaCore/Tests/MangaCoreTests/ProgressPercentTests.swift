import XCTest
@testable import MangaCore

private let serverID = UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!
private let ref = SeriesRef(serverID: serverID, seriesID: "1")

private func chapter(_ n: Int, pages: Int = 20, lastPage: Int = 0, read: Bool = false) -> Chapter {
    Chapter(id: "\(n)", seriesRef: ref, title: "Chapter \(n)", number: Double(n), pageCount: pages,
            lastPageRead: lastPage, isRead: read)
}

private func detail(_ chapters: [Chapter]) -> SeriesDetail {
    SeriesDetail(summary: SeriesSummary(ref: ref, title: "T", coverURL: nil), synopsis: nil, authors: [],
                 genres: [], status: nil, chapters: chapters)
}

/// The percentage next to poster progress bars, and posters picking up
/// progress made after their row loaded (John, 2026-11-26: "after reading,
/// it does not get reflected on the progress bar").
final class ProgressPercentTests: XCTestCase {
    func testPercentText() {
        XCTAssertEqual(PosterBadges.percentText(0), "0%")
        XCTAssertEqual(PosterBadges.percentText(2.0 / 11), "18%")
        XCTAssertEqual(PosterBadges.percentText(0.5), "50%")
        XCTAssertEqual(PosterBadges.percentText(1), "100%")
        XCTAssertEqual(PosterBadges.percentText(0.001), "1%", "something read is never 0%")
        XCTAssertEqual(PosterBadges.percentText(0.998), "99%", "not finished is never 100%")
        XCTAssertEqual(PosterBadges.percentText(1.4), "100%")
        XCTAssertEqual(PosterBadges.percentText(-1), "0%")
    }

    func testSuwayomiPosterUpdatesAfterReading() {
        // The row loaded with nothing read: 11 unread, empty bar.
        let listed = SeriesSummary(ref: ref, title: "T", coverURL: nil, unreadCount: 11, chapterCount: 11)
        XCTAssertEqual(PosterBadges(series: listed, caption: .progress).titleProgress, 0)
        XCTAssertEqual(PosterBadges(series: listed).corner, .unread(11))
        // Then two chapters were read and the third started.
        let chapters = (1...11).map { n in chapter(n, lastPage: n == 3 ? 8 : 0, read: n <= 2) }
        let fresh = SeriesProgressOverride(detail: detail(chapters)).applied(to: listed)
        let badges = PosterBadges(series: fresh, caption: .progress)
        XCTAssertEqual(badges.corner, .unread(9))
        XCTAssertEqual(badges.titleProgress!, 2.0 / 11, accuracy: 0.0001)
        XCTAssertEqual(PosterBadges.percentText(badges.titleProgress!), "18%")
        XCTAssertNil(fresh.pagesRead, "a chapter-based listing stays chapter-based")
    }

    func testKavitaPosterKeepsPageProgress() {
        let listed = SeriesSummary(ref: ref, title: "T", coverURL: nil, unreadCount: 80, pageCount: 80, pagesRead: 0)
        let chapters = [chapter(1, read: true), chapter(2, lastPage: 10), chapter(3), chapter(4)]
        let fresh = SeriesProgressOverride(detail: detail(chapters)).applied(to: listed)
        XCTAssertEqual(fresh.pageCount, 80)
        XCTAssertEqual(fresh.pagesRead, 30)
        let badges = PosterBadges(series: fresh, caption: .progress)
        XCTAssertEqual(badges.titleProgress!, 30.0 / 80, accuracy: 0.0001)
        XCTAssertEqual(badges.progress!, 30.0 / 80, accuracy: 0.0001, "the cover bar moves too")
    }

    func testFinishedAfterReading() {
        let listed = SeriesSummary(ref: ref, title: "T", coverURL: nil, unreadCount: 3, chapterCount: 3)
        let fresh = SeriesProgressOverride(detail: detail([chapter(1, read: true), chapter(2, read: true),
                                                           chapter(3, read: true)])).applied(to: listed)
        XCTAssertEqual(PosterBadges(series: fresh).corner, .finished)
    }

    func testMarkedUnreadClearsTheBar() {
        let listed = SeriesSummary(ref: ref, title: "T", coverURL: nil, unreadCount: 40, pageCount: 80, pagesRead: 40)
        let fresh = SeriesProgressOverride(detail: detail((1...4).map { chapter($0) })).applied(to: listed)
        XCTAssertEqual(fresh.pagesRead, 0)
        XCTAssertNil(PosterBadges(series: fresh).progress)
    }

    func testPagesUnknownFallsBackToChapters() {
        let listed = SeriesSummary(ref: ref, title: "T", coverURL: nil, unreadCount: 40, pageCount: 80, pagesRead: 40)
        let fresh = SeriesProgressOverride(detail: detail([chapter(1, pages: 0, read: true), chapter(2, pages: 0)]))
            .applied(to: listed)
        XCTAssertNil(fresh.pagesRead)
        XCTAssertEqual(fresh.unreadCount, 1)
        XCTAssertEqual(fresh.chapterCount, 2)
        XCTAssertEqual(PosterBadges(series: fresh, caption: .progress).titleProgress!, 0.5, accuracy: 0.0001)
    }

    func testVolumeCountIsKept() {
        var listed = SeriesSummary(ref: ref, title: "T", coverURL: nil, unreadCount: 5, chapterCount: 5)
        listed.countUnit = .volume
        let fresh = SeriesProgressOverride(detail: detail((1...5).map { chapter($0, pages: 0, read: $0 == 1) }))
            .applied(to: listed)
        XCTAssertEqual(fresh.chapterCount, 5)
        XCTAssertEqual(fresh.countUnit, .volume)
    }

    func testShowsPercentIsOnByDefaultAndSaved() throws {
        XCTAssertTrue(BrowsePreferences().showsProgressPercent)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(BrowsePreferences()), as: UTF8.self), "{}")
        var prefs = BrowsePreferences()
        prefs.showsProgressPercent = false
        let data = try JSONEncoder().encode(prefs)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"showsProgressPercent":false}"#)
        XCTAssertFalse(try JSONDecoder().decode(BrowsePreferences.self, from: data).showsProgressPercent)
        XCTAssertTrue(try JSONDecoder().decode(BrowsePreferences.self, from: Data(#"{"showsProgressPercent":"x"}"#.utf8))
            .showsProgressPercent, "bad values fall back to on")
    }
}
