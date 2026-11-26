import XCTest

/// Drives the book reader on the demo book (`-readerDemo -readerBook`):
/// public-domain "Alice's Adventures in Wonderland", Part One (three EPUB
/// sections with a table of contents) and Part Two (plain text).
///
/// `book.page`'s value is "<section>.<page>", both one-based.
final class BookReaderUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerBook"]
        app.launch()
        XCTAssertTrue(element("book.reader").waitForExistence(timeout: 15))
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        expectPage("1.1")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private var page: XCUIElement { element("book.page") }

    private var pageValue: String { (page.value as? String) ?? "" }

    private func expectPage(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: page)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed,
                       "Expected page \(value), got \(page.exists ? pageValue : "<missing>")", file: file, line: line)
    }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 8,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format)", file: file, line: line)
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func moveFocus(to id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "No \(id)", file: file, line: line)
        for _ in 0..<30 {
            if target.hasFocus { return }
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
    }

    private func openMenu() {
        remote.press(.playPause)
        XCTAssertTrue(element("book.menu").waitForExistence(timeout: 5))
        wait(element("book.menu.size.larger"), "hasFocus == true")
    }

    // MARK: Tests

    func testTurnsPagesForwardAndBack() {
        launch()
        XCTAssertTrue(page.label.contains("Alice was beginning"), page.label)
        XCTAssertTrue(app.staticTexts["book.position"].label.hasPrefix("Page 1 of "))
        remote.press(.right)
        expectPage("1.2")
        remote.press(.left)
        expectPage("1.1")
        // Nothing before the first page of the first chapter.
        remote.press(.left)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(element("book.edge").exists)
        expectPage("1.1")
    }

    func testCrossesSectionsAndChapters() {
        launch()
        // Walk to section 2.
        for _ in 0..<12 where !pageValue.hasPrefix("2.") {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.4)
        }
        expectPage("2.1")
        XCTAssertTrue(page.label.contains("Curiouser and curiouser"), page.label)
        // Back across the section edge lands on section 1's last page.
        remote.press(.left)
        wait(page, "value BEGINSWITH '1.'")
        remote.press(.right)
        expectPage("2.1")
        // On to the end of Part One, then into Part Two (plain text).
        for _ in 0..<12 where !element("book.edge").exists {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(element("book.edge").waitForExistence(timeout: 5))
        XCTAssertTrue(element("book.edge").label.contains("Part Two"), element("book.edge").label)
        remote.press(.right)
        expectPage("1.1")
        XCTAssertTrue(page.label.contains("White Rabbit, trotting"), page.label)
    }

    func testSettingsApplyLive() {
        launch()
        openMenu()
        let size = app.staticTexts["book.menu.size.value"]
        let start = size.label
        remote.press(.select)
        wait(size, "label != '\(start)'")

        let menu = MenuRowDriver(app: app, prefix: "book.menu")
        menu.pick("theme.sepia")
        menu.expectValue("theme", "Sepia")

        menu.pick("columns.1")
        menu.expectValue("columns", "One")

        // Menu goes back from an open list first, then closes the drawer.
        menu.press("font")
        XCTAssertTrue(element("book.menu.font.title").waitForExistence(timeout: 5))
        remote.press(.menu)
        wait(element("book.menu.font"), "hasFocus == true")

        remote.press(.menu)
        wait(element("book.menu"), "exists == false")
        expectPage("1.1")
        remote.press(.right)
        expectPage("1.2")
    }

    func testContentsJumpsToEntry() {
        launch()
        openMenu()
        moveFocus(to: "book.menu.tab.contents")
        remote.press(.select)
        XCTAssertTrue(element("book.toc.3").waitForExistence(timeout: 5))
        moveFocus(to: "book.toc.3")
        remote.press(.select)
        wait(element("book.menu"), "exists == false")
        expectPage("3.1")
        XCTAssertTrue(page.label.contains("queer-looking party"), page.label)
    }

    /// Settings / Contents are tabs like the top bar, not radio options.
    func testSectionTabsLookLikeTheTopBar() {
        launch()
        openMenu()
        let ids = ["book.menu.tab.settings", "book.menu.tab.contents"]
        assertSectionTabLayout(app, track: "book.menu.tabs", tabs: ids, titles: ["Settings", "Contents"])
        XCTAssertTrue(element("book.menu.tab.settings").isSelected)
        moveFocus(to: "book.menu.tab.contents")
        remote.press(.select)
        wait(element("book.menu.tab.contents"), "isSelected == true")
        XCTAssertFalse(element("book.menu.tab.settings").isSelected)
    }
}

