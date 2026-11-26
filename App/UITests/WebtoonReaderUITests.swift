import XCTest

/// Drives the vertical (webtoon) reader on the built-in demo series
/// (`-readerDemo -readerMode webtoon`). Chapter 1: 6 pages, sizes known up
/// front, page 4 wide. Chapter 2: 5 pages, sizes only known after loading,
/// page 3 wide. Chapter 3: 4 pages. Demo pages are 400×600 (wide 800×600),
/// so at the default 60% column on a 1920-point screen a tall page is
/// 1728 points high and one click moves 810 points.
final class WebtoonReaderUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerMode", "webtoon"] + extra
        app.launch()
        XCTAssertTrue(indicator.waitForExistence(timeout: 15), "webtoon reader didn't open")
    }

    private var indicator: XCUIElement { app.staticTexts["reader.webtoon.indicator"] }
    private var window: CGRect { app.windows.firstMatch.frame }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func page(_ chapter: Int, _ index: Int) -> XCUIElement { element("reader.webtoon.page.demo-\(chapter).\(index)") }

    private func expectIndicator(_ text: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: indicator)
        let result = XCTWaiter().wait(for: [exp], timeout: timeout)
        XCTAssertEqual(result, .completed,
                       "Expected \"\(text)\", got \"\(indicator.exists ? indicator.label : "<missing>")\"",
                       file: file, line: line)
    }

    private func waitForLoaded(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) missing", file: file, line: line)
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'loaded'"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed, "\(element) never loaded", file: file, line: line)
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            // Let the glide settle so each click is measured on its own.
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    private func assertJoined(_ upper: XCUIElement, _ lower: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitForLoaded(upper, file: file, line: line)
        waitForLoaded(lower, file: file, line: line)
        XCTAssertEqual(upper.frame.maxY, lower.frame.minY, accuracy: 0.01, "gap or overlap between pages", file: file, line: line)
        XCTAssertEqual(upper.frame.minX, lower.frame.minX, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(upper.frame.width, lower.frame.width, accuracy: 0.01, file: file, line: line)
    }

    // MARK: Layout

    func testPagesAreJoinedWithNoGapInACenteredColumn() {
        launch()
        expectIndicator("Chapter 1 · 1 / 6")
        assertJoined(page(1, 0), page(1, 1))
        let frame = page(1, 0).frame
        XCTAssertEqual(frame.width, window.width * 0.6, accuracy: 1)
        XCTAssertEqual(frame.midX, window.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, window.minY, accuracy: 0.5)
        XCTAssertEqual(frame.height, frame.width * 1.5, accuracy: 0.5, "height follows the page's aspect ratio")
    }

    func testWidePageJoinsItsNeighbours() {
        launch(["-readerStartPage", "3"])
        expectIndicator("Chapter 1 · 4 / 6")
        assertJoined(page(1, 3), page(1, 4))
        let wide = page(1, 3).frame
        XCTAssertEqual(wide.height, wide.width * 0.75, accuracy: 0.5)
    }

    func testFullWidthSetting() {
        launch(["-readerWebtoonWidth", "1.0"])
        expectIndicator("Chapter 1 · 1 / 6")
        waitForLoaded(page(1, 0))
        XCTAssertEqual(page(1, 0).frame.width, window.width, accuracy: 0.5)
    }

    // MARK: Remote

    func testClickScrollsByStepAndHoldScrollsContinuously() {
        launch()
        expectIndicator("Chapter 1 · 1 / 6")
        let before = page(1, 0).frame.minY
        press(.down)
        XCTAssertEqual(page(1, 0).frame.minY, before - window.height * 0.75, accuracy: 1,
                       "one click moves 75% of a screen; strip: \(String(describing: element("reader.webtoon.strip").value)), window \(window)")
        press(.down, times: 2)
        expectIndicator("Chapter 1 · 2 / 6")
        press(.up)
        expectIndicator("Chapter 1 · 1 / 6")
        remote.press(.down, forDuration: 2.5)
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (label IN %@)", ["Chapter 1 · 1 / 6", "Chapter 1 · 2 / 6"]),
            object: indicator)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed,
                       "holding down should scroll several pages, got \(indicator.label)")
    }

    func testClickRightSnapsToNextPage() {
        launch()
        expectIndicator("Chapter 1 · 1 / 6")
        press(.right)
        expectIndicator("Chapter 1 · 2 / 6")
        XCTAssertEqual(page(1, 1).frame.minY, window.minY, accuracy: 1)
        press(.left)
        expectIndicator("Chapter 1 · 1 / 6")
    }

    func testClickOpensMenuAndScrollingWorksAfterClosingIt() {
        launch()
        expectIndicator("Chapter 1 · 1 / 6")
        remote.holdPlayPause()
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        remote.press(.menu)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element("reader.menu"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        let strip = element("reader.webtoon.strip")
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH 'focused'"), object: strip)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed,
                       "strip should take focus back, value=\(strip.exists ? String(describing: strip.value) : "<missing>")\n\(app.debugDescription)")
        press(.down, times: 3)
        expectIndicator("Chapter 1 · 2 / 6")
    }

    // MARK: Chapters

    func testScrollingPastTheEndJoinsTheNextChapterSeamlessly() {
        launch(["-readerStartPage", "5"])
        expectIndicator("Chapter 1 · 6 / 6")
        press(.down, times: 2)
        let divider = element("reader.webtoon.break")
        XCTAssertTrue(divider.waitForExistence(timeout: 5), "chapter divider should be in the strip")
        XCTAssertEqual(divider.label, "Chapter 2")
        press(.down, times: 2)
        expectIndicator("Chapter 2 · 1 / 5")
        XCTAssertFalse(element("reader.loading").exists, "the next chapter loads without a spinner")
        // Scrolling back up returns to chapter 1 in the same strip.
        press(.up, times: 3)
        expectIndicator("Chapter 1 · 6 / 6")
    }

    func testEndOfSeriesFooter() {
        launch(["-readerStartChapter", "3", "-readerStartPage", "3"])
        expectIndicator("Chapter 3 · 4 / 4")
        press(.down, times: 3)
        XCTAssertTrue(element("reader.webtoon.end").waitForExistence(timeout: 5))
        expectIndicator("Chapter 3 · 4 / 4")
    }

    // MARK: Sizes learned while reading

    func testResumeStaysPutWhileUnknownSizesArrive() {
        // Chapter 2's sizes are unknown until the images load, and page 3
        // (above the resume point) turns out to be wide. The page we resumed
        // on must stay at the top of the screen.
        launch(["-readerStartChapter", "2", "-readerStartPage", "3"])
        expectIndicator("Chapter 2 · 4 / 5")
        waitForLoaded(page(2, 3))
        waitForLoaded(page(2, 2))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(page(2, 3).frame.minY, window.minY, accuracy: 1, "content jumped when sizes arrived")
        expectIndicator("Chapter 2 · 4 / 5")
        assertJoined(page(2, 3), page(2, 4))
    }

    func testFarPagesAreRecycled() {
        launch()
        expectIndicator("Chapter 1 · 1 / 6")
        XCTAssertTrue(page(1, 0).exists)
        press(.down, times: 6)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: page(1, 0))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "off-screen page view should be released")
    }
}
