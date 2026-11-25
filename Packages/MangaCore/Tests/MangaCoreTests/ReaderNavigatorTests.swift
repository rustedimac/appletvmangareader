import XCTest
@testable import MangaCore

final class ReaderNavigatorTests: XCTestCase {
    let tall = PageSize(width: 800, height: 1200)
    let wide = PageSize(width: 1600, height: 1200)

    func nav(_ count: Int, start: Int = 0, settings: ReaderSettings = ReaderSettings()) -> ReaderNavigator {
        ReaderNavigator(sizes: Array(repeating: tall, count: count), settings: settings, startPage: start)
    }

    func testStartsOnSpreadContainingStartPage() {
        // cover, 1-2, 3-4, 5
        XCTAssertEqual(nav(6, start: 0).currentSpread, .single(0))
        XCTAssertEqual(nav(6, start: 2).currentSpread, .double(1, 2))
        XCTAssertEqual(nav(6, start: 2).currentPage, 1)
        XCTAssertEqual(nav(6, start: 99).currentSpread, .single(5))
        XCTAssertEqual(nav(6, start: -3).currentSpread, .single(0))
    }

    func testForwardThroughChapterThenTransitionThenLeave() {
        var n = nav(4) // 0, 1-2, 3
        XCTAssertEqual(n.forward(), .moved)
        XCTAssertEqual(n.visiblePages, [1, 2])
        XCTAssertEqual(n.forward(), .moved)
        XCTAssertEqual(n.visiblePages, [3])
        XCTAssertTrue(n.isChapterComplete)
        XCTAssertEqual(n.forward(), .showTransition(.end))
        XCTAssertEqual(n.edge, .end)
        XCTAssertEqual(n.visiblePages, [])
        XCTAssertEqual(n.forward(), .leaveChapter(.end))
        // Backing out of the card returns to the last spread.
        XCTAssertEqual(n.backward(), .moved)
        XCTAssertNil(n.edge)
        XCTAssertEqual(n.visiblePages, [3])
    }

    func testBackwardFromFirstSpreadShowsStartCard() {
        var n = nav(4)
        XCTAssertEqual(n.backward(), .showTransition(.start))
        XCTAssertEqual(n.backward(), .leaveChapter(.start))
        XCTAssertEqual(n.forward(), .moved)
        XCTAssertNil(n.edge)
        XCTAssertEqual(n.visiblePages, [0])
    }

    func testEmptyChapterDoesNothing() {
        var n = nav(0)
        XCTAssertEqual(n.forward(), .none)
        XCTAssertEqual(n.backward(), .none)
        XCTAssertNil(n.currentSpread)
        XCTAssertFalse(n.isChapterComplete)
    }

    func testRemoteDirectionFollowsReadingDirection() {
        var rtl = nav(6)
        XCTAssertEqual(rtl.turn(.left), .moved)
        XCTAssertEqual(rtl.visiblePages, [1, 2])
        XCTAssertEqual(rtl.turn(.right), .moved)
        XCTAssertEqual(rtl.visiblePages, [0])

        var ltrSettings = ReaderSettings()
        ltrSettings.direction = .leftToRight
        var ltr = nav(6, settings: ltrSettings)
        XCTAssertEqual(ltr.turn(.right), .moved)
        XCTAssertEqual(ltr.visiblePages, [1, 2])
        XCTAssertEqual(ltr.turn(.left), .moved)
        XCTAssertEqual(ltr.visiblePages, [0])
    }

    func testLateWideSizeKeepsCurrentPageOnScreen() {
        // Suwayomi: sizes unknown at first.
        var n = ReaderNavigator(pageCount: 8, settings: ReaderSettings(), startPage: 5)
        XCTAssertEqual(n.currentSpread, .double(5, 6))
        // Page 3 turns out to be a wide spread: 0, 1-2, [3], 4-5, 6-7.
        XCTAssertTrue(n.setSize(wide, forPage: 3))
        XCTAssertEqual(n.layout.spreads, [.single(0), .double(1, 2), .single(3), .double(4, 5), .double(6, 7)])
        XCTAssertEqual(n.currentSpread, .double(4, 5))
        XCTAssertTrue(n.visiblePages.contains(5))
    }

    func testTallSizeDoesNotRelayout() {
        var n = ReaderNavigator(pageCount: 4, settings: ReaderSettings())
        XCTAssertFalse(n.setSize(tall, forPage: 1))
        XCTAssertEqual(n.sizes[1], tall)
        XCTAssertFalse(n.setSize(tall, forPage: 99))
    }

    func testShiftSettingKeepsAnchor() {
        var n = nav(8, start: 3) // 0, 1-2, 3-4, 5-6, 7
        XCTAssertEqual(n.currentSpread, .double(3, 4))
        var s = n.settings
        s.shiftPairing = true // 0-1, 2-3, 4-5, 6-7
        XCTAssertTrue(n.updateSettings(s))
        XCTAssertEqual(n.currentSpread, .double(2, 3))
    }

    func testSingleLayoutSetting() {
        var n = nav(4, start: 2)
        var s = n.settings
        s.layout = .single
        n.updateSettings(s)
        XCTAssertEqual(n.currentSpread, .single(1))
        XCTAssertEqual(n.layout.count, 4)
    }

    func testGoToPageHidesTransition() {
        var n = nav(4)
        _ = n.backward()
        n.go(toPage: 3)
        XCTAssertNil(n.edge)
        XCTAssertEqual(n.visiblePages, [3])
    }

    func testProgressPageIsLastVisiblePage() {
        var n = nav(6)
        _ = n.forward()
        XCTAssertEqual(n.progressPage, 2)
        XCTAssertFalse(n.isChapterComplete)
    }

    func testPreloadNearestFirst() {
        let n = nav(10, start: 4) // 0, 1-2, 3-4, 5-6, 7-8, 9
        XCTAssertEqual(n.pagesToPreload(radius: 2), [3, 4, 5, 6, 1, 2, 7, 8, 0])
        XCTAssertEqual(n.pagesToPreload(radius: 0), [3, 4])
        XCTAssertEqual(nav(0).pagesToPreload(), [])
    }

    // MARK: Geometry

    func testSpreadFramesShareHeightAndTouch() {
        let frames = SpreadGeometry.frames(for: [tall, PageSize(width: 760, height: 1200)], in: 1920, 1080, scale: 2)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].height, frames[1].height)
        XCTAssertEqual(frames[0].height, 1080)
        // No seam: the second page starts where the first ends.
        XCTAssertEqual(frames[0].x + frames[0].width, frames[1].x)
        // Centered and inside the container.
        XCTAssertGreaterThanOrEqual(frames[0].x, 0)
        XCTAssertLessThanOrEqual(frames[1].x + frames[1].width, 1920)
        let left = frames[0].x
        let right = 1920 - (frames[1].x + frames[1].width)
        XCTAssertLessThanOrEqual(abs(left - right), 0.5)
    }

    func testFramesSnapToPixels() {
        let frames = SpreadGeometry.frames(for: [PageSize(width: 777, height: 1111), PageSize(width: 701, height: 1093)],
                                           in: 1919, 1077, scale: 2)
        for f in frames {
            XCTAssertEqual((f.x * 2).rounded(), f.x * 2)
            XCTAssertEqual((f.width * 2).rounded(), f.width * 2)
            XCTAssertEqual((f.height * 2).rounded(), f.height * 2)
        }
        XCTAssertEqual(frames[0].x + frames[0].width, frames[1].x)
    }

    func testWideSpreadFitsWidth() {
        let frames = SpreadGeometry.frames(for: [PageSize(width: 3000, height: 1000)], in: 1920, 1080)
        XCTAssertEqual(frames[0].width, 1920)
        XCTAssertEqual(frames[0].height, 640)
        XCTAssertEqual(frames[0].y, 220)
    }

    func testFramesNeverOverflowAfterRounding() {
        for w in stride(from: 300.0, through: 2000, by: 37) {
            let frames = SpreadGeometry.frames(for: [PageSize(width: w, height: 1000), PageSize(width: 1001, height: 999)],
                                               in: 1920, 1080, scale: 2)
            let right = frames[1].x + frames[1].width
            XCTAssertLessThanOrEqual(right, 1920.0001)
            XCTAssertLessThanOrEqual(frames[0].height, 1080)
        }
    }

    func testUnknownSizeUsesPlaceholderAspect() {
        let frames = SpreadGeometry.frames(for: [nil], in: 1920, 1000)
        XCTAssertEqual(frames[0].width, 700)
        XCTAssertEqual(SpreadGeometry.frames(for: [], in: 100, 100), [])
    }
}
