import XCTest

/// The touch reader on iPhone and iPad (docs/IOS.md §3) on the demo series,
/// which reads right to left: forward is a left tap or a swipe to the right.
final class ReaderTouchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"] + extra
        app.launch()
        let reader = element(extra.contains("webtoon") ? "reader.webtoon.strip" : "reader.paged")
        XCTAssertTrue(reader.waitForExistence(timeout: 15), "Reader did not appear:\n\(app.debugDescription)")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private var window: XCUIElement { app.windows.firstMatch }
    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func expectPage(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let label = element("reader.chrome.pageNumber")
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 5), .completed,
                       "Expected \(text), got \(label.exists ? label.label : "<no page number>")", file: file, line: line)
    }

    func testSwipeTurnsFollowingReadingDirection() {
        launch()
        expectPage("1 / 6")
        // Right to left: dragging the page to the right brings the next one.
        point(0.2, 0.5).press(forDuration: 0.05, thenDragTo: point(0.85, 0.5))
        expectPage("2 / 6")
        point(0.85, 0.5).press(forDuration: 0.05, thenDragTo: point(0.2, 0.5))
        expectPage("1 / 6")
    }

    func testSideTapsTurnAndHideTheControls() {
        launch()
        expectPage("1 / 6")
        point(0.1, 0.5).tap()
        XCTAssertTrue(element("reader.chrome").waitForNonExistence(timeout: 3), "A turn should hide the controls")
        point(0.5, 0.5).tap()
        XCTAssertTrue(element("reader.chrome").waitForExistence(timeout: 3))
        expectPage("2 / 6")
    }

    func testPinchZoomsAndDoubleTapResets() {
        launch()
        let reader = element("reader.paged")
        reader.pinch(withScale: 2.5, velocity: 2)
        XCTAssertTrue(element("reader.zoom").waitForExistence(timeout: 5), "Pinch didn't zoom")
        // Zoomed, a side tap doesn't turn.
        point(0.1, 0.5).tap()
        expectPageStays("1 / 6")
        reader.doubleTap()
        XCTAssertTrue(element("reader.zoom").waitForNonExistence(timeout: 5), "Double-tap didn't zoom out")
        reader.doubleTap()
        XCTAssertTrue(element("reader.zoom").waitForExistence(timeout: 5), "Double-tap didn't zoom in")
    }

    private func expectPageStays(_ text: String) {
        // The controls may be hidden; show them to read the number. Wait
        // first so two taps don't count as a double-tap (zoom).
        sleep(1)
        if !element("reader.chrome").exists { point(0.5, 0.5).tap() }
        expectPage(text)
    }

    func testOptionsOpenWithTapZones() {
        launch()
        element("reader.chrome.options").tap()
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5), "Options didn't open")
        let tapZones = element("reader.menu.tapZones")
        // The sheet may need a scroll to reach the last row.
        for _ in 0..<6 where !tapZones.isHittable { element("reader.menu").swipeUp() }
        XCTAssertTrue(tapZones.exists, "No Tap Zones row:\n\(app.debugDescription)")
        tapZones.tap()
        let off = element("reader.menu.tapZones.off")
        XCTAssertTrue(off.waitForExistence(timeout: 3))
        off.tap()
        // Close the options; with Tap Zones off a side tap only toggles.
        element("reader.options.done").tap()
        XCTAssertTrue(element("reader.menu").waitForNonExistence(timeout: 5), "Options didn't close")
        point(0.1, 0.5).tap()
        expectPageStays("1 / 6")
    }

    func testCloseButtonClosesTheReader() {
        launch(["-readerDemoCover"])
        XCTAssertTrue(element("reader.chrome.close").waitForExistence(timeout: 5))
        element("reader.chrome.close").tap()
        XCTAssertTrue(element("demo.openReader").waitForExistence(timeout: 5), "Reader didn't close")
    }

    func testPortraitShowsSinglePagesLandscapeSpreads() {
        XCUIDevice.shared.orientation = .portrait
        launch()
        point(0.1, 0.5).tap()  // to page 2 (the cover is always alone)
        XCTAssertTrue(element("reader.page.1").waitForExistence(timeout: 5))
        XCTAssertFalse(element("reader.page.2").exists, "Portrait should show one page")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(element("reader.page.2").waitForExistence(timeout: 5),
                      "Landscape should pair pages 2 and 3:\n\(app.debugDescription)")
        XCTAssertTrue(element("reader.page.1").exists)
    }

    func testVerticalReaderSideTapsScroll() {
        launch(["-readerMode", "webtoon"])
        expectPage("1 / 6")
        point(0.9, 0.5).tap()
        point(0.5, 0.5).tap()
        let label = element("reader.chrome.pageNumber")
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != '1 / 6'"), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "Right tap didn't scroll down")
    }
}
