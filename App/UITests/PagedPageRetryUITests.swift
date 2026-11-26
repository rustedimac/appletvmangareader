import XCTest

/// Failing pages in the paged reader, using the demo series with
/// `-readerPageFaults` (the demo server fails or hangs chosen requests) and
/// the demo's short retry policy: two attempts per load, 1.5 s each.
/// Default layout is right-to-left double pages: page 1 alone, then 2–3.
final class PagedPageRetryUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(faults: String, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerPageFaults", faults] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["reader.paged"].waitForExistence(timeout: 15),
                      "reader didn't open")
    }

    private var indicator: XCUIElement { app.staticTexts["reader.pageIndicator"] }
    private func page(_ index: Int) -> XCUIElement { app.descendants(matching: .any)["reader.page.\(index)"] }

    private func wait(_ element: XCUIElement, value: String, timeout: TimeInterval = 15,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) missing", file: file, line: line)
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never became \(value); value is \(String(describing: element.value))",
                       file: file, line: line)
    }

    private func expectIndicator(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: indicator)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed,
                       "indicator: \(indicator.exists ? indicator.label : "<missing>")", file: file, line: line)
    }

    func testOneFailedRequestIsRetriedAutomatically() {
        launch(faults: "1.0=fail1")
        wait(page(0), value: "loaded")
    }

    func testHangingRequestTimesOutAndIsRetried() {
        launch(faults: "1.0=hang1")
        wait(page(0), value: "loaded")
    }

    func testSelectRetriesAFailedPageInPlace() {
        launch(faults: "1.0=fail2")
        wait(page(0), value: "failed")
        XCTAssertEqual(page(0).label, "Page 1 didn't load")
        remote.press(.select)
        wait(page(0), value: "loaded")
        expectIndicator("1 / 6")
    }

    func testFailedPageInASpreadDoesNotStopTheOtherOrTurning() {
        // Page 3 (index 2) never loads; page 2 beside it does.
        launch(faults: "1.2=fail999")
        expectIndicator("1 / 6")
        remote.press(.left)
        expectIndicator("2–3 / 6")
        wait(page(1), value: "loaded")
        wait(page(2), value: "failed")
        remote.press(.select)
        wait(page(2), value: "failed")
        // Still in the chapter, and the next spread opens normally.
        remote.press(.left)
        expectIndicator("4 / 6")
        wait(page(3), value: "loaded")
        // Coming back shows the failure again rather than a spinner forever.
        remote.press(.right)
        expectIndicator("2–3 / 6")
        wait(page(2), value: "failed")
    }
}
