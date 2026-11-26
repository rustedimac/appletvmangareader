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
        // The bar's top edge sits 46 pt down (DESIGN_GUIDE §2); its buttons sit below that.
        XCTAssertGreaterThanOrEqual(before.minY, 40, "tab bar off screen before scrolling: \(before)", file: file, line: line)

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
            XCTAssertGreaterThanOrEqual(button.frame.minY, 40, "\(button.label) clipped: \(button.frame)",
                                        file: file, line: line)
        }
        attachScreenshot(app, name: "tab bar after focusing it (\(tabName))")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTabBarFullyVisibleAfterScrollingHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"]
        app.launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        assertTabBarComesBack(app, tabName: "Home", presses: 4)
    }

    /// John's case: Home with an "isn't signed in" message above the first
    /// row. The message has nothing to focus, so Up from the first row goes
    /// straight to the tab bar.
    func testTabBarFullyVisibleOnHomeUnderSignedOutMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers", "-demoSignedOut"]
        app.launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "isn't signed in to Demo Kavita"))
        XCTAssertTrue(message.firstMatch.exists, "no signed-out message on Home")
        // One press down reaches the first row; then two more rows down.
        assertTabBarComesBack(app, tabName: "Home", presses: 1)
        assertTabBarComesBack(app, tabName: "Home", presses: 3)
    }

    /// All six tabs fit the bar: none is cut off at the screen edge and the
    /// bar never scrolls sideways when focus moves along it.
    func testAllTabsFitInTheBar() {
        let names = ["Home", "Library", "Favorites", "Bookmarks", "Search", "Settings"]
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        let home = focusTabBar(app)
        XCTAssertEqual(home.label, "Home")
        let screen = app.windows.firstMatch.frame
        let bar = app.tabBars.firstMatch.frame

        func frames() -> [String: CGRect] {
            Dictionary(uniqueKeysWithValues: names.map { ($0, app.tabBars.buttons[$0].frame) })
        }
        let start = frames()
        attachScreenshot(app, name: "tab bar, Home focused")
        // Walk focus to Settings; a bar that scrolls sideways moves its items.
        for _ in 0..<(names.count - 1) {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.tabBars.buttons["Settings"].hasFocus, "focus didn't reach Settings: \(focusedDescription())")
        let end = frames()
        attachScreenshot(app, name: "tab bar, Settings focused")

        for name in names {
            for (when, frame) in [("Home focused", start[name]!), ("Settings focused", end[name]!)] {
                XCTAssertFalse(frame.isEmpty, "\(name) has no frame (\(when))")
                XCTAssertGreaterThanOrEqual(frame.minX, max(screen.minX, bar.minX) - 1,
                                            "\(name) cut off on the left (\(when)): \(frame), bar \(bar)")
                XCTAssertLessThanOrEqual(frame.maxX, min(screen.maxX, bar.maxX) + 1,
                                         "\(name) cut off on the right (\(when)): \(frame), bar \(bar)")
                XCTAssertGreaterThanOrEqual(frame.minY, 40, "\(name) cut off at the top (\(when)): \(frame)")
            }
            // Focused items grow a little; anything more is the bar scrolling.
            XCTAssertEqual(start[name]!.midX, end[name]!.midX, accuracy: 12,
                           "the bar scrolled sideways: \(name) moved from \(start[name]!) to \(end[name]!)")
        }
        // In order, without overlapping.
        for (a, b) in zip(names, names.dropFirst()) {
            XCTAssertLessThanOrEqual(start[a]!.maxX, start[b]!.minX + 1, "\(a) overlaps \(b)")
        }
    }

    func testTabBarFullyVisibleAfterScrollingSettings() {
        let app = XCUIApplication.launched(seed: "servers", tab: "settings")
        assertTabBarComesBack(app, tabName: "Settings", presses: 10)
    }
}
