import XCTest

/// Failing pages in the webtoon reader, using the demo series with
/// `-readerPageFaults` (the demo server fails or hangs chosen requests) and
/// the demo's short retry policy: two attempts per load, 1.5 s each.
final class WebtoonPageRetryUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(faults: String) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerMode", "webtoon", "-readerPageFaults", faults]
        app.launch()
        XCTAssertTrue(indicator.waitForExistence(timeout: 15), "webtoon reader didn't open")
    }

    private var indicator: XCUIElement { app.staticTexts["reader.webtoon.indicator"] }
    private func page(_ chapter: Int, _ index: Int) -> XCUIElement {
        app.descendants(matching: .any)["reader.webtoon.page.demo-\(chapter).\(index)"]
    }

    private func wait(_ element: XCUIElement, value: String, timeout: TimeInterval = 15,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) missing", file: file, line: line)
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never became \(value); value is \(String(describing: element.value))",
                       file: file, line: line)
    }

    func testOneFailedRequestIsRetriedAutomatically() {
        launch(faults: "1.0=fail1")
        wait(page(1, 0), value: "loaded")
    }

    func testHangingRequestTimesOutAndIsRetried() {
        launch(faults: "1.0=hang1")
        wait(page(1, 0), value: "loaded")
    }

    func testSelectRetriesAFailedPageInPlace() {
        // Chapter 1's sizes are known up front, so nothing prefetches page 1
        // ahead of its own load: the fault count maps to its attempts.
        // Both automatic attempts fail; the third request (the user's retry) works.
        launch(faults: "1.0=fail2")
        wait(page(1, 0), value: "failed")
        XCTAssertEqual(page(1, 0).label, "Page 1 didn't load")
        remote.press(.select)
        wait(page(1, 0), value: "loaded")
        // Still reading the same chapter; Select didn't open the menu.
        XCTAssertEqual(indicator.label, "Chapter 1 · 1 / 6")
        XCTAssertFalse(app.descendants(matching: .any)["reader.menu"].exists)
    }

    func testAPageThatNeverLoadsDoesNotBlockReading() {
        launch(faults: "1.0=fail999")
        wait(page(1, 0), value: "failed")
        remote.press(.select)
        // The retry fails too, and the reader stays open on the failed page.
        wait(page(1, 0), value: "failed")
        XCTAssertTrue(indicator.exists)
        // Reading on past it works.
        remote.press(.right)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Chapter 1 · 2 / 6"),
                                              object: indicator)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 10), .completed, "indicator: \(indicator.label)")
        wait(page(1, 1), value: "loaded")
        // With the failed page scrolled away, Select opens the menu as usual.
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["reader.menu"].waitForExistence(timeout: 5))
    }
}
