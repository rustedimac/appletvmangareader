import XCTest

/// Guest sessions (see `GuestSession`): a guest starts with none of the
/// owner's favorites, can't reach servers or sync settings, and ending the
/// session brings the owner's data back unchanged.
final class GuestUITests: XCTestCase {
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func press(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            usleep(350_000)
        }
        return element.exists && element.hasFocus
    }

    private func selectTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let anyTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        if !anyTab.exists { _ = press(.up, until: anyTab, max: 8) }
        XCTAssertTrue(anyTab.exists, "tab bar never took focus")
        if press(.right, until: tab, max: 6) { return }
        XCTAssertTrue(press(.left, until: tab, max: 6), "couldn't focus the \(name) tab")
    }

    func testGuestStartsEmptyAndEndingBringsBackTheOwnersFavorites() {
        let app = XCUIApplication.launched(tab: "settings", extra: ["-demoServers", "-demoFavorites"])
        // Guest is the last section, below the servers.
        if focus(app.element("settings.startGuest"), .down, maxPresses: 18) { remote.press(.select) }

        // Settings now shows the guest, without servers or sync.
        XCTAssertTrue(app.element("settings.endGuest").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("settings.readerDefaults").exists)
        XCTAssertFalse(app.element("settings.addServer").exists)
        XCTAssertFalse(app.element("settings.icloud").exists)
        XCTAssertFalse(app.element("settings.switchProfile").exists)

        selectTab(app, "Favorites")
        XCTAssertTrue(app.staticTexts["No favorites yet"].waitForExistence(timeout: 10))

        selectTab(app, "Settings")
        select(app.element("settings.endGuest"))
        XCTAssertTrue(app.element("settings.startGuest").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("settings.addServer").exists)

        selectTab(app, "Favorites")
        XCTAssertTrue(app.buttons["favorites.sort.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No favorites yet"].exists)
    }

    func testGuestFromWhoIsReadingReturnsToThePicker() {
        let app = XCUIApplication.launched(seed: "profiles", tab: "settings")
        XCTAssertTrue(app.staticTexts["Who's reading?"].waitForExistence(timeout: 10))
        select(app.element("profilePicker.guest"), .right)
        XCTAssertTrue(app.element("settings.endGuest").waitForExistence(timeout: 10))
        XCTAssertFalse(app.element("settings.manageProfiles").exists)

        select(app.element("settings.endGuest"))
        // Back to "Who's reading?" with the real profiles, and no guest left in them.
        XCTAssertTrue(app.staticTexts["Who's reading?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("profilePicker.Me").exists)
        XCTAssertTrue(app.element("profilePicker.Kid").exists)
        XCTAssertFalse(app.element("profilePicker.Guest").exists)
    }
}
