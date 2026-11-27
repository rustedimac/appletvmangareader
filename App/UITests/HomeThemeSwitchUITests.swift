import XCTest

/// Changing the theme rebuilds every screen. Home has to come back with
/// the rows it already had, not only the fastest source while the servers
/// load again. The demo servers answer every call after 6 seconds here
/// (`-demoLatency`), so rows that show within 3 seconds of the switch can
/// only be the ones Home kept.
final class HomeThemeSwitchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        // One row per server, so each server's row can be found.
        app = XCUIApplication.launched(tab: "home", extra: ["-demoServers", "-homePerServer", "-demoLatency", "6000"])
    }

    private func shelf(_ server: String) -> XCUIElement {
        app.element("shelfRow.\(server).recentlyUpdated")
    }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let anyTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<30 where !anyTab.exists {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(anyTab.exists, "tab bar never took focus")
        if focus(tab, .right, maxPresses: 6) { XCUIRemote.shared.press(.select) }
    }

    private func pickTheme(_ title: String) {
        selectTab("Settings")
        select(app.element("settings.theme"))
        let option = app.element("settingsPicker.option.\(title)")
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        select(option)
        XCTAssertTrue(app.element("settings.theme").waitForExistence(timeout: 10))
    }

    func testHomeKeepsServerRowsAcrossThemeChanges() {
        XCTAssertTrue(shelf("Demo Kavita").waitForExistence(timeout: 30), "first load")
        XCTAssertTrue(shelf("Demo Suwayomi").waitForExistence(timeout: 10))

        // Default to a theme and back: both rebuild every screen.
        for theme in ["Celadon", "Default"] {
            pickTheme(theme)
            selectTab("Home")
            XCTAssertTrue(shelf("Demo Kavita").waitForExistence(timeout: 3),
                          "[\(theme)] Home lost Demo Kavita's rows and is loading them again")
            XCTAssertTrue(shelf("Demo Suwayomi").exists, "[\(theme)] Home lost Demo Suwayomi's rows")
        }
    }
}
