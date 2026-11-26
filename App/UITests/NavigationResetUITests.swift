import XCTest

/// A tab goes back to its top screen once it has been out of sight for a
/// while (10 s in the app, shortened here with
/// `-uiTestingNavigationResetDelay`). See NavigationReset.swift.
final class NavigationResetUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(tab: String, resetDelay: Int) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingTab", tab,
                               "-uiTestingNavigationResetDelay", String(resetDelay)]
        app.launch()
    }

    private var focusedTab: XCUIElement {
        app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Moves focus up into the tab bar, then sideways onto `name` (which
    /// selects that tab on tvOS).
    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        for _ in 0..<12 where !focusedTab.exists {
            remote.press(.up)
            usleep(350_000)
        }
        XCTAssertTrue(focusedTab.exists, "tab bar never took focus")
        for direction in [XCUIRemote.Button.left, .right] {
            for _ in 0..<6 where !tab.hasFocus {
                remote.press(direction)
                usleep(350_000)
            }
        }
        XCTAssertTrue(tab.hasFocus, "couldn't focus the \(name) tab")
    }

    private var customizeHomeScreen: XCUIElement { app.element("homeLayout.reset") }

    private func openCustomizeHomeFromSettings() {
        select(app.element("settings.customizeHome"))
        XCTAssertTrue(customizeHomeScreen.waitForExistence(timeout: 10), "Customize Home didn't open")
    }

    func testSettingsReturnsToTopLevelAfterBeingAway() {
        launch(tab: "settings", resetDelay: 2)
        openCustomizeHomeFromSettings()

        selectTab("Search")
        Thread.sleep(forTimeInterval: 4)
        selectTab("Settings")

        XCTAssertTrue(app.element("settings.customizeHome").waitForExistence(timeout: 5),
                      "Settings didn't go back to its main list")
        XCTAssertFalse(customizeHomeScreen.exists, "Customize Home is still showing")
    }

    func testSettingsKeepsSubScreenWhenBackQuickly() {
        launch(tab: "settings", resetDelay: 60)
        openCustomizeHomeFromSettings()

        selectTab("Search")
        selectTab("Settings")

        XCTAssertTrue(customizeHomeScreen.waitForExistence(timeout: 5),
                      "Customize Home closed although Settings was only left briefly")
    }

    /// Home pushes by value (a NavigationPath), so this covers clearing the path.
    func testHomeReturnsToTopLevelAfterBeingAway() {
        launch(tab: "home", resetDelay: 2)
        select(app.element("home.customize"))
        XCTAssertTrue(customizeHomeScreen.waitForExistence(timeout: 10), "Customize Home didn't open")

        selectTab("Library")
        Thread.sleep(forTimeInterval: 4)
        selectTab("Home")

        XCTAssertTrue(app.element("home.customize").waitForExistence(timeout: 5),
                      "Home didn't go back to its rows")
        XCTAssertFalse(customizeHomeScreen.exists, "Customize Home is still showing on Home")
    }
}
