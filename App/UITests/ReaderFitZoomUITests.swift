import XCTest

/// Fit modes, hold-to-zoom and border cropping in the paged reader, on the
/// demo series (`-readerDemo`). Chapter 1 reads 1 | 2–3 | 4 | 5–6 in
/// right-to-left two-page layout; its pages are 400×600 (page 4 is 800×600).
///
/// The page indicator's accessibility value reports the viewport as
/// "zoom Z x X y Y" (X and Y are 0–1 across what can be panned).
final class ReaderFitZoomUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"] + extra
        app.launch()
        XCTAssertTrue(element("reader.paged").waitForExistence(timeout: 15))
        expectIndicator("1 / 6")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func menuItem(_ id: String) -> XCUIElement { element("reader.menu.\(id)") }
    private var indicator: XCUIElement { app.staticTexts["reader.pageIndicator"] }

    private func expectIndicator(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        wait(indicator, "label == '\(text)'", file: file, line: line)
    }

    /// Waits for the viewport description to contain `fragment`, e.g. "y 0.48".
    private func expectViewport(_ fragment: String, file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", fragment),
                                            object: indicator)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 5), .completed,
                       "Expected viewport with \"\(fragment)\", got \"\(indicator.value as? String ?? "<none>")\"",
                       file: file, line: line)
    }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format)", file: file, line: line)
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func openMenu() {
        remote.holdPlayPause()
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        wait(menuItem("mode"), "hasFocus == true", timeout: 5)
    }

    private var menu: MenuRowDriver { MenuRowDriver(app: app, prefix: "reader.menu") }

    private func closeMenu() {
        remote.press(.menu)
        wait(element("reader.menu"), "exists == false", timeout: 5)
    }

    /// Moves focus to a menu control with up/down then left/right.
    private func choose(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = menuItem(id)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "No \(id)", file: file, line: line)
        for _ in 0..<30 {
            if target.hasFocus { break }
            let current = focused
            guard current.exists else { Thread.sleep(forTimeInterval: 0.3); continue }
            let a = current.frame, b = target.frame
            if b.midY > a.maxY { remote.press(.down) }
            else if b.midY < a.minY { remote.press(.up) }
            else if b.midX > a.midX { remote.press(.right) }
            else { remote.press(.left) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(target.hasFocus, "Couldn't move focus to \(id)", file: file, line: line)
        remote.press(.select)
    }

    // MARK: Fit

    func testFitWidthScrollsThroughATallPageBeforeTurning() {
        launch(["-readerFit", "width"])
        expectViewport("y 0.00")
        // The page is 2880 points tall at full width; each press pans 80%
        // of the screen (864 of 1800 points of travel).
        remote.press(.left)
        expectViewport("y 0.48")
        expectIndicator("1 / 6")
        remote.press(.left)
        expectViewport("y 0.96")
        remote.press(.left)
        expectViewport("y 1.00")
        expectIndicator("1 / 6")
        // At the bottom, forward turns, and the next spread opens at its top.
        remote.press(.left)
        expectIndicator("2–3 / 6")
        expectViewport("y 0.00")
        // Backward from the top goes back to the previous page's bottom.
        remote.press(.right)
        expectIndicator("1 / 6")
        expectViewport("y 1.00")
        // Up pans; down at the bottom doesn't open the menu.
        remote.press(.up)
        expectViewport("y 0.52")
        remote.press(.down)
        expectViewport("y 1.00")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(element("reader.menu").exists)
    }

    func testFitWidthPageFillsTheScreenWidth() {
        launch(["-readerFit", "width", "-readerLayout", "single"])
        let page = element("reader.page.0")
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame.width, app.frame.width, accuracy: 2)
        XCTAssertGreaterThan(page.frame.height, app.frame.height * 2)
    }

    func testFitModeChangesFromTheMenuAndIsSelected() {
        launch()
        openMenu()
        menu.expectValue("fit", "Fit Screen")
        menu.expectValue("cropBorders", "Off")
        menu.expectValue("zoom", "2×")
        menu.pick("fit.width")
        menu.expectValue("fit", "Fit Width")
        closeMenu()
        // Now the cover scrolls before turning.
        remote.press(.left)
        expectViewport("y 0.48")
        expectIndicator("1 / 6")
    }

    // MARK: Zoom

    /// Holding Select zooms in (docs/READER_CONTROLS.md section 10).
    private func holdToZoom() {
        remote.press(.select, forDuration: 1.0)
    }

    func testHoldingSelectZoomsInAndMenuZoomsOut() {
        launch()
        XCTAssertFalse(element("reader.zoom").exists)
        // A plain click doesn't zoom.
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(element("reader.zoom").exists)
        holdToZoom()
        XCTAssertTrue(element("reader.zoom").waitForExistence(timeout: 5))
        expectViewport("zoom 2.00 x 0.50 y 0.50")
        XCTAssertFalse(element("reader.menu").exists, "holding Select no longer opens the options")
        // Forward pans across the zoomed page instead of turning.
        remote.press(.left)
        expectViewport("x 0.00 y 0.50")
        expectIndicator("1 / 6")
        // Menu zooms out and keeps the reader open.
        remote.press(.menu)
        wait(element("reader.zoom"), "exists == false", timeout: 5)
        expectViewport("zoom 1.00")
        XCTAssertTrue(element("reader.paged").exists)
    }

    func testClickZoomsOut() {
        launch()
        holdToZoom()
        expectViewport("zoom 2.00")
        remote.press(.select)
        wait(element("reader.zoom"), "exists == false", timeout: 5)
        expectViewport("zoom 1.00")
        expectIndicator("1 / 6")
    }

    func testZoomedPageTurnsAtTheEdgeWithoutDroppingARow() {
        launch()
        holdToZoom()
        expectViewport("zoom 2.00 x 0.50 y 0.50")
        // Up to the top half, then left to the left edge.
        remote.press(.up)
        expectViewport("y 0.00")
        remote.press(.left)
        expectViewport("x 0.00 y 0.00")
        expectIndicator("1 / 6")
        // Left again, at the left edge: the page turns (no drop to the
        // next row), and the zoom resets on the new spread.
        remote.press(.left)
        expectIndicator("2–3 / 6")
        expectViewport("zoom 1.00 x 1.00 y 0.00")
        XCTAssertFalse(element("reader.zoom").exists)
    }

    func testZoomLevelFromTheMenu() {
        launch()
        openMenu()
        menu.pick("zoom.3x")
        menu.expectValue("zoom", "3×")
        closeMenu()
        holdToZoom()
        expectViewport("zoom 3.00")
    }

    // MARK: Crop

    func testCropBordersTrimsMarginsAndKeepsSpreadsSeamless() {
        launch(["-readerDemoMargins", "1"])
        let cover = element("reader.page.0")
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        wait(cover, "value == 'loaded'")
        let uncroppedWidth = cover.frame.width
        openMenu()
        menu.setToggle("cropBorders", on: true)
        closeMenu()
        wait(cover, "value == 'cropped'")
        // The page still fills the screen's height; its shape follows the
        // trimmed art (the demo margins are wider at the sides).
        XCTAssertEqual(cover.frame.height, app.frame.height, accuracy: 2)
        XCTAssertNotEqual(cover.frame.width, uncroppedWidth, accuracy: 2)

        remote.press(.left)
        expectIndicator("2–3 / 6")
        let p1 = element("reader.page.1"), p2 = element("reader.page.2")
        wait(p1, "value == 'cropped'")
        wait(p2, "value == 'cropped'")
        // Right to left: page 2 is on the left, page 3 on the right, touching.
        XCTAssertEqual(p2.frame.maxX, p1.frame.minX, accuracy: 1)
        XCTAssertEqual(p1.frame.height, p2.frame.height, accuracy: 1)
        XCTAssertEqual(p1.frame.minY, p2.frame.minY, accuracy: 1)
    }

    func testCropCanBeTurnedOffAgain() {
        launch(["-readerDemoMargins", "1", "-readerCrop", "1"])
        wait(element("reader.page.0"), "value == 'cropped'")
        openMenu()
        menu.expectValue("cropBorders", "On")
        menu.setToggle("cropBorders", on: false)
        closeMenu()
        wait(element("reader.page.0"), "value == 'loaded'")
    }
}
