import XCTest

/// The top tab bar slides up as a screen scrolls. When focus goes back up to
/// it from a scrolled screen, the whole bar has to come back on screen, not
/// stay two-thirds visible (see `TabBarScrollReset`).
final class TabBarVisibilityUITests: XCTestCase {
    let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func focusedTab(_ app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Presses Up until a tab has focus, then lets the bar settle.
    private func focusTabBar(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let tab = focusedTab(app)
        for _ in 0..<14 where !tab.exists {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(tab.exists, "the tab bar never took focus. Focus: \(focusedDescription())", file: file, line: line)
        // Let the scroll and the tab bar slide finish.
        Thread.sleep(forTimeInterval: 1.5)
        return tab
    }

    /// Scrolls down `presses` times, goes back up to the tab bar and checks
    /// the bar sits where it did before scrolling.
    private func assertTabBarComesBack(_ app: XCUIApplication, tabName: String, presses: Int,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[tabName]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), file: file, line: line)
        let before = focusTabBar(app, file: file, line: line).frame
        XCTAssertGreaterThanOrEqual(before.minY, 0, "tab bar off screen before scrolling: \(before)", file: file, line: line)

        for _ in 0..<presses {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(focusedTab(app).exists, "focus never left the tab bar", file: file, line: line)

        let after = focusTabBar(app, file: file, line: line).frame
        XCTAssertGreaterThanOrEqual(after.minY, before.minY - 2,
                                    "tab bar still partly off screen after focusing it: \(after) vs \(before)",
                                    file: file, line: line)
        XCTAssertEqual(after.height, before.height, accuracy: 2, file: file, line: line)
        for button in app.tabBars.buttons.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(button.frame.minY, 0, "\(button.label) clipped: \(button.frame)",
                                        file: file, line: line)
        }
    }

    func testTabBarFullyVisibleAfterScrollingHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"]
        app.launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        assertTabBarComesBack(app, tabName: "Home", presses: 4)
    }

    func testTabBarFullyVisibleAfterScrollingSettings() {
        let app = XCUIApplication.launched(seed: "servers", tab: "settings")
        assertTabBarComesBack(app, tabName: "Settings", presses: 10)
    }
}
