import XCTest

/// iPhone and iPad smoke checks (docs/IOS.md §7): the app launches, every
/// tab opens, and the demo reader answers taps.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A tab's button: in the bottom tab bar (iPhone, compact iPad) or in
    /// the iPad top tab bar / sidebar.
    private func tabButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let inBar = app.tabBars.buttons[title]
        if inBar.exists { return inBar }
        return app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    func testLaunchOpensEveryTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let home = tabButton("Home", in: app)
        XCTAssertTrue(home.waitForExistence(timeout: 15), "No Home tab:\n\(app.debugDescription)")
        // Bookmarks is in the bar only in regular width (IOSMainTabs).
        // Search goes last: on iPhone the bar collapses while it's open.
        var titles = ["Library", "Favorites", "Settings", "Home", "Search"]
        if UIDevice.current.userInterfaceIdiom == .pad { titles.insert("Bookmarks", at: 2) }
        for title in titles {
            let tab = tabButton(title, in: app)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "No \(title) tab:\n\(app.debugDescription)")
            tab.tap()
            XCTAssertEqual(app.state, .runningForeground, "App left the foreground after \(title)")
        }
    }

    /// iPhone has no Bookmarks tab; Favorites opens it. iPad has the tab.
    func testBookmarksReachableOnEveryDevice() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingTab", "favorites"]
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(tabButton("Bookmarks", in: app).waitForExistence(timeout: 10))
        } else {
            let button = app.buttons["favorites.bookmarks"]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "No Bookmarks button in Favorites:\n\(app.debugDescription)")
            button.tap()
            XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 5), "Bookmarks didn't open")
        }
    }

    func testDemoReaderTapZones() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"]
        app.launch()
        let reader = app.descendants(matching: .any)["reader.paged"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15), "Reader did not appear:\n\(app.debugDescription)")
        let chrome = app.descendants(matching: .any)["reader.chrome"]
        XCTAssertTrue(chrome.waitForExistence(timeout: 5), "Chrome hidden at open")

        // Centre tap hides the chrome, a second one brings it back.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(chrome.waitForNonExistence(timeout: 3), "Centre tap didn't hide the chrome")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(chrome.waitForExistence(timeout: 3), "Centre tap didn't show the chrome")

        // The demo is right-to-left: the left third goes forward.
        XCTAssertTrue(app.descendants(matching: .any)["reader.page.0"].waitForExistence(timeout: 10))
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["reader.page.1"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["reader.page.1.right"].exists
                      || app.descendants(matching: .any)["reader.page.1.left"].exists,
                      "Left tap didn't turn forward:\n\(app.debugDescription)")
    }
}
