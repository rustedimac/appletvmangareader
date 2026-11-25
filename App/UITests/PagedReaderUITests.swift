import XCTest

/// Drives the paged reader on the built-in demo series (`-readerDemo`).
/// Chapter 1 has 6 pages with page 4 a wide spread, chapter 2 has 5 pages
/// whose sizes are only known after loading (page 3 wide), chapter 3 has 4.
final class PagedReaderUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["reader.paged"].waitForExistence(timeout: 15))
    }

    private var indicator: XCUIElement { app.staticTexts["reader.pageIndicator"] }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func expectIndicator(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", text)
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: indicator)
        let result = XCTWaiter().wait(for: [exp], timeout: 10)
        XCTAssertEqual(result, .completed,
                       "Expected page indicator \"\(text)\", got \"\(indicator.exists ? indicator.label : "<missing>")\"",
                       file: file, line: line)
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
        }
    }

    func testRightToLeftTurnsThroughChapterIntoNext() {
        launch()
        expectIndicator("1 / 6")          // cover alone
        press(.left)
        expectIndicator("2–3 / 6")
        XCTAssertTrue(element("reader.page.1").exists)
        XCTAssertTrue(element("reader.page.2").exists)
        press(.left)
        expectIndicator("4 / 6")          // wide spread alone
        press(.left)
        expectIndicator("5–6 / 6")
        press(.left)
        XCTAssertTrue(element("reader.transition").waitForExistence(timeout: 5))
        XCTAssertEqual(element("reader.transition.target").label, "Chapter 2")
        press(.left)
        expectIndicator("1 / 5")          // chapter 2 opens on its first page
        XCTAssertFalse(element("reader.transition").exists)
    }

    func testBackwardIntoPreviousChapterOpensOnLastSpread() {
        launch(["-readerStartChapter", "2"])
        expectIndicator("1 / 5")
        press(.right)
        XCTAssertTrue(element("reader.transition").waitForExistence(timeout: 5))
        XCTAssertEqual(element("reader.transition.target").label, "Chapter 1")
        press(.right)
        expectIndicator("5–6 / 6")
    }

    func testTransitionCardCanBeBackedOutOf() {
        launch(["-readerStartChapter", "3", "-readerStartPage", "3"])
        expectIndicator("4 / 4")
        press(.left)
        XCTAssertTrue(element("reader.transition.none").waitForExistence(timeout: 5))
        press(.right)
        expectIndicator("4 / 4")
    }

    func testLeftToRightDirection() {
        launch(["-readerDirection", "leftToRight"])
        expectIndicator("1 / 6")
        press(.right)
        expectIndicator("2–3 / 6")
        press(.left)
        expectIndicator("1 / 6")
    }

    func testSizesLearnedWhileReadingFixPairing() {
        // Chapter 2's page 3 is wide but the server doesn't say so. Once
        // it loads, page 2 must stand alone instead of pairing with it.
        launch(["-readerStartChapter", "2"])
        expectIndicator("1 / 5")
        press(.left)
        expectIndicator("2 / 5")
        press(.left)
        expectIndicator("3 / 5")
        press(.left)
        expectIndicator("4–5 / 5")
    }

    func testSinglePageLayout() {
        launch(["-readerLayout", "single"])
        expectIndicator("1 / 6")
        press(.left)
        expectIndicator("2 / 6")
        press(.left)
        expectIndicator("3 / 6")
    }

    func testSpreadPagesAreJoinedWithoutGap() {
        launch()
        press(.left)
        expectIndicator("2–3 / 6")
        let first = element("reader.page.1")   // right-hand page in RTL
        let second = element("reader.page.2")  // left-hand page in RTL
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(second.frame.maxX, first.frame.minX, accuracy: 1)
        XCTAssertEqual(second.frame.height, first.frame.height, accuracy: 1)
        XCTAssertEqual(second.frame.minY, first.frame.minY, accuracy: 1)
    }

    func testSwipeDownOpensMenuAndMenuButtonClosesIt() {
        launch()
        expectIndicator("1 / 6")
        press(.down)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        press(.menu)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element("reader.menu"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        // Focus returns to the page, so turning still works.
        press(.left)
        expectIndicator("2–3 / 6")
    }
}
