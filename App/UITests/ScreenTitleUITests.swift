import XCTest

/// Settings screens draw their title inside the scrolling Form, so it
/// scrolls away with the rows and comes back at the top instead of staying
/// pinned over them.
final class ScreenTitleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func titleIsAboveFirstRow(_ app: XCUIApplication, firstRow: XCUIElement) -> Bool {
        let title = app.element("screen.title")
        return title.exists && title.frame.maxY <= firstRow.frame.minY + 1 && title.frame.minY >= 0
    }

    func testReaderDefaultsTitleScrollsAwayAndBack() {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.readerDefaults"))
        checkTitleScrolls(app, first: app.element("readerDefaults.mode"), last: app.element("readerDefaults.reset"))
    }

    func testServerEditorTitleScrollsAwayAndBack() {
        let app = XCUIApplication.launched(seed: "servers", tab: "settings")
        select(app.element("settings.server.Test Kavita"))
        checkTitleScrolls(app, first: app.element("serverEditor.name"), last: app.element("serverEditor.remove"))
    }

    func testFreeLibraryTitleScrollsAwayAndBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-freeLibrary", "-uiTestingTab", "settings"]
        app.launch()
        select(app.element("settings.server.Free Library"))
        checkTitleScrolls(app, first: app.element("freeLibrary.credit.0"), last: app.element("freeLibrary.remove"))
    }

    private func checkTitleScrolls(_ app: XCUIApplication, first: XCUIElement, last: XCUIElement,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(first.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(focus(first, .up), file: file, line: line)
        XCTAssertTrue(titleIsAboveFirstRow(app, firstRow: first), "title should start above the first row", file: file, line: line)

        // Scroll to the bottom: the title must not sit on top of the rows.
        XCTAssertTrue(focus(last, .down, maxPresses: 14), file: file, line: line)
        Thread.sleep(forTimeInterval: 0.6)
        let title = app.element("screen.title")
        if title.exists, title.frame.maxY > 0 {
            XCTAssertLessThanOrEqual(title.frame.maxY, first.frame.minY + 1, "title is drawn over the rows", file: file, line: line)
        }

        // Back to the top: the title is visible above the first row again.
        XCTAssertTrue(focus(first, .up, maxPresses: 14), file: file, line: line)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(titleIsAboveFirstRow(app, firstRow: first), "title didn't come back above the first row", file: file, line: line)
    }
}
