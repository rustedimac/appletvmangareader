import XCTest
@testable import MangaCore

final class ReaderTouchTests: XCTestCase {
    func testRegionsAreThirds() {
        XCTAssertEqual(TapRegion(x: 10, width: 300), .left)
        XCTAssertEqual(TapRegion(x: 150, width: 300), .center)
        XCTAssertEqual(TapRegion(x: 290, width: 300), .right)
        XCTAssertEqual(TapRegion(x: 99.9, width: 300), .left)
        XCTAssertEqual(TapRegion(x: 200, width: 300), .right)
        XCTAssertEqual(TapRegion(x: 5, width: 0), .center)
    }

    func testCenterAlwaysTogglesChrome() {
        for zones in TapZones.allCases {
            for mode in ReadingMode.allCases {
                XCTAssertEqual(ReaderTouch.tap(.center, zones: zones, mode: mode, direction: .rightToLeft), .toggleChrome)
            }
        }
    }

    func testEdgesTurnBySide() {
        XCTAssertEqual(ReaderTouch.tap(.left, zones: .edges, mode: .paged, direction: .rightToLeft), .turn(.left))
        XCTAssertEqual(ReaderTouch.tap(.right, zones: .edges, mode: .paged, direction: .leftToRight), .turn(.right))
    }

    func testLeftHandedBothSidesGoForward() {
        // Right-to-left manga goes forward with a left press.
        XCTAssertEqual(ReaderTouch.tap(.left, zones: .leftHanded, mode: .paged, direction: .rightToLeft), .turn(.left))
        XCTAssertEqual(ReaderTouch.tap(.right, zones: .leftHanded, mode: .paged, direction: .rightToLeft), .turn(.left))
        XCTAssertEqual(ReaderTouch.tap(.left, zones: .leftHanded, mode: .paged, direction: .leftToRight), .turn(.right))
    }

    func testOffAndZoomedOnlyToggle() {
        XCTAssertEqual(ReaderTouch.tap(.left, zones: .off, mode: .paged, direction: .leftToRight), .toggleChrome)
        XCTAssertEqual(ReaderTouch.tap(.right, zones: .edges, mode: .paged, direction: .leftToRight, zoomed: true),
                       .toggleChrome)
    }

    func testVerticalReaderScrolls() {
        XCTAssertEqual(ReaderTouch.tap(.left, zones: .edges, mode: .webtoon, direction: .leftToRight), .scroll(forward: false))
        XCTAssertEqual(ReaderTouch.tap(.right, zones: .edges, mode: .webtoon, direction: .rightToLeft), .scroll(forward: true))
        XCTAssertEqual(ReaderTouch.tap(.left, zones: .leftHanded, mode: .webtoon, direction: .leftToRight), .scroll(forward: true))
    }

    func testSwipeTurns() {
        // Finger to the left = like pressing right.
        XCTAssertEqual(ReaderTouch.swipeTurn(dx: -120, velocity: -100, width: 400), .right)
        XCTAssertEqual(ReaderTouch.swipeTurn(dx: 120, velocity: 100, width: 400), .left)
        // Short and slow: no turn.
        XCTAssertNil(ReaderTouch.swipeTurn(dx: -30, velocity: -100, width: 400))
        // Short but flung: turn.
        XCTAssertEqual(ReaderTouch.swipeTurn(dx: -30, velocity: -900, width: 400), .right)
        // Flung back against the drag: no turn.
        XCTAssertNil(ReaderTouch.swipeTurn(dx: -30, velocity: 900, width: 400))
        // Mostly vertical: no turn.
        XCTAssertNil(ReaderTouch.swipeTurn(dx: -120, dy: 300, velocity: -900, width: 400))
    }

    func testZoomRules() {
        XCTAssertEqual(ReaderTouch.clampedZoom(0.5), 1)
        XCTAssertEqual(ReaderTouch.clampedZoom(9), 4)
        XCTAssertEqual(ReaderTouch.clampedZoom(.nan), 1)
        XCTAssertEqual(ReaderTouch.doubleTapTarget(currentZoom: 1), 2)
        XCTAssertEqual(ReaderTouch.doubleTapTarget(currentZoom: 2.5), 1)
        XCTAssertEqual(ReaderTouch.doubleTapTarget(currentZoom: 1, zoomScale: 3), 3)
    }

    func testPortraitShowsSinglePages() {
        XCTAssertEqual(ReaderTouch.effectiveLayout(.double, portrait: true), .single)
        XCTAssertEqual(ReaderTouch.effectiveLayout(.double, portrait: false), .double)
        XCTAssertEqual(ReaderTouch.effectiveLayout(.single, portrait: false), .single)
    }

    func testTapZonesDecodeTolerantly() throws {
        let old = try JSONDecoder().decode(ReaderSettings.self, from: Data(#"{"mode":"paged"}"#.utf8))
        XCTAssertEqual(old.tapZones, .edges)
        let unknown = try JSONDecoder().decode(ReaderSettings.self, from: Data(#"{"tapZones":"diagonal"}"#.utf8))
        XCTAssertEqual(unknown.tapZones, .edges)
    }

    func testMenuShowsTapZonesOnlyOnTouch() {
        XCTAssertFalse(ReaderMenuOptions.items(for: .default).contains(.tapZones))
        XCTAssertEqual(ReaderMenuOptions.items(for: .default, touch: true).last, .tapZones)
    }
}
