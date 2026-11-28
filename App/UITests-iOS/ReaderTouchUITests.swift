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

    /// Closes the options like a person: drags the iPhone sheet down by its
    /// top edge (it may have grown to full height), taps outside the iPad
    /// popover.
    private func closeOptions() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            point(0.3, 0.6).tap()
            return
        }
        let panel: CGRect = element("reader.options.panel").frame
        let screen: CGRect = window.frame
        let origin: XCUICoordinate = window.coordinate(withNormalizedOffset: .zero)
        // The grabber strip above the rows (dragging inside the rows scrolls them).
        let grab = origin.withOffset(CGVector(dx: panel.midX, dy: max(screen.minY + 2, panel.minY - 6)))
        let drop = origin.withOffset(CGVector(dx: panel.midX, dy: screen.maxY - 10))
        grab.press(forDuration: 0.1, thenDragTo: drop)
        // Fallback: swipe down until the rows are back at the top and the sheet follows.
        for _ in 0..<4 where element("reader.menu").exists {
            sleep(1)
            if element("reader.menu").exists { element("reader.menu").swipeDown(velocity: .fast) }
        }
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
        // The system pop-up menu: items are buttons named by their titles.
        let off = app.buttons["Off"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 3), "No pop-up menu:\n\(app.debugDescription)")
        off.tap()
        // Close the options (no Done button) once the pop-up menu has gone;
        // with Tap Zones off a side tap only toggles.
        sleep(1)
        closeOptions()
        XCTAssertTrue(element("reader.menu").waitForNonExistence(timeout: 5), "Options didn't close")
        point(0.1, 0.5).tap()
        expectPageStays("1 / 6")
    }

    /// A choice row opens the system pop-up menu; picking an item updates
    /// the row's value and the options stay open (no in-place list).
    func testChoiceRowOpensPopUpMenu() {
        launch()
        element("reader.chrome.options").tap()
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        let mode = app.buttons["reader.menu.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 3), "No Reading Mode row:\n\(app.debugDescription)")
        XCTAssertEqual(mode.value as? String, "Paged")
        mode.tap()
        let vertical = app.buttons["Vertical Scroll"].firstMatch
        XCTAssertTrue(vertical.waitForExistence(timeout: 3), "No pop-up menu:\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Press Menu to go back without changing it."].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "A keyboard came up with the menu")
        vertical.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Vertical Scroll'"), object: mode)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed, "Row didn't show the new value")
        XCTAssertTrue(element("reader.menu").exists, "Options closed after picking")
        XCTAssertTrue(element("reader.webtoon.strip").waitForExistence(timeout: 5), "Reader didn't switch mode")
        XCTAssertFalse(app.buttons["reader.options.done"].exists, "No Done button on iOS")
    }

    /// Right after a pick, the row's value sits fully inside the panel (it
    /// used to show cut off while the label animated its width).
    func testPickedValueShowsAtFullWidthAtOnce() {
        launch()
        element("reader.chrome.options").tap()
        let panel = element("reader.options.panel")
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let mode = app.buttons["reader.menu.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 3))
        for choice in ["Vertical Scroll", "Paged"] {
            mode.tap()
            let item = app.buttons[choice].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3), "No \(choice) in the menu")
            item.tap()
            // No waiting: read the frame straight away.
            let row: CGRect = mode.frame
            let bounds: CGRect = panel.frame
            XCTAssertEqual(mode.value as? String, choice)
            XCTAssertGreaterThanOrEqual(row.minX, bounds.minX, "Value starts outside the panel after picking \(choice)")
            XCTAssertLessThanOrEqual(row.maxX, bounds.maxX, "Value ends outside the panel after picking \(choice)")
            XCTAssertGreaterThanOrEqual(row.width, 60, "Value squeezed (\(row.width) pt) after picking \(choice)")
            sleep(1)
        }
    }

    /// The speed row is a − value + stepper like Column Width; playing is the
    /// chrome's Play button, not a button in the options.
    func testSpeedRowIsAStepper() {
        launch(["-readerMode", "webtoon"])
        element("reader.chrome.options").tap()
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        let value = app.staticTexts["reader.menu.autoScroll.value"]
        let faster = app.buttons["reader.menu.autoScroll.faster"]
        for _ in 0..<6 where !(faster.exists && faster.isHittable) { element("reader.menu").swipeUp() }
        XCTAssertTrue(faster.exists, "No speed stepper:\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["reader.menu.autoScroll.start"].exists, "Start belongs to the reader controls on iOS")
        let before = value.label
        faster.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: value)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 3), .completed, "+ didn't change the speed")
        app.buttons["reader.menu.autoScroll.slower"].tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", before), object: value)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 3), .completed, "− didn't change the speed back")
    }

    /// Tapping outside the options closes them (sheet on iPhone, popover on iPad).
    func testTapOutsideClosesOptions() {
        launch()
        element("reader.chrome.options").tap()
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        point(0.5, 0.1).tap()
        XCTAssertTrue(element("reader.menu").waitForNonExistence(timeout: 5), "Tap outside didn't close the options")
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

    func testLongPressBookmarksThePage() {
        launch()
        let bookmark = element("reader.chrome.bookmark")
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        XCTAssertEqual(bookmark.label, "Bookmark This Page")
        point(0.5, 0.5).press(forDuration: 1.0)
        // iPad shows the dialog as a popover whose button can appear twice.
        let menuItem = app.buttons["reader.pageMenu.bookmark"].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "No page menu:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["reader.pageMenu.share"].firstMatch.exists)
        menuItem.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Remove Bookmark'"), object: bookmark)
        XCTAssertEqual(XCTWaiter().wait(for: [removed], timeout: 5), .completed, "Page wasn't bookmarked")
    }

    func testOrientationLockTurnsTheReader() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPad apps with Split View can't lock orientation")
        XCUIDevice.shared.orientation = .portrait
        launch()
        element("reader.chrome.options").tap()
        let row = element("reader.menu.orientationLock")
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        for _ in 0..<6 where !(row.exists && row.isHittable) { element("reader.menu").swipeUp() }
        row.tap()
        // The reader turns right away, options still open.
        let landscape = app.buttons["Landscape"].firstMatch
        XCTAssertTrue(landscape.waitForExistence(timeout: 3))
        landscape.tap()
        defer { XCUIDevice.shared.orientation = .portrait }
        let wide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let f = self.app.windows.firstMatch.frame
            return f.width > f.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [wide], timeout: 8), .completed, "Reader didn't turn to landscape")
    }

    func testVerticalReaderSideTapsScroll() {
        launch(["-readerMode", "webtoon"])
        expectPage("1 / 6")
        // Full-width pages can be taller than the screen: two steps.
        point(0.9, 0.5).tap()
        sleep(1)
        point(0.9, 0.5).tap()
        sleep(1)
        point(0.5, 0.5).tap()
        let label = element("reader.chrome.pageNumber")
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != '1 / 6'"), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "Right tap didn't scroll down")
    }
}
