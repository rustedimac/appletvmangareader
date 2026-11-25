import XCTest

/// The app running as the current Apple TV user (`-appleTVUserMode`): the
/// Apple TV user is the profile, and servers are shared between users.
final class AppleTVUserUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-appleTVUserMode", "-uiTestingTab", "settings"] + extra
        app.launch()
        return app
    }

    func testOpensStraightIntoTheAppleTVUsersProfile() {
        let app = launch([])
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Who's reading?"].exists)
        XCTAssertTrue(app.element("settings.appleTVUser").waitForExistence(timeout: 5))
        // In-app profile switching is hidden: the Apple TV user is the profile.
        XCTAssertFalse(app.element("settings.switchProfile").exists)
        XCTAssertFalse(app.element("settings.manageProfiles").exists)
    }

    func testOlderStateWithSeveralProfilesSkipsPickerAndOpensLastPicked() {
        let app = launch(["-uiTestingSeed", "profiles", "-uiTestingRememberProfile", "Kid"])
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Who's reading?"].exists)
        XCTAssertTrue(app.staticTexts["Kid"].waitForExistence(timeout: 5))
        // Those profiles are still reachable.
        XCTAssertTrue(app.element("settings.switchProfile").exists)
    }

    func testServersAddedByAnotherUserAppearWithTheirLogin() {
        let app = launch(["-uiTestingSharedServers"])
        let row = app.element("settings.server.Family Kavita")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // The shared login is used, so the row doesn't ask for an API key.
        XCTAssertFalse(app.staticTexts["No API key"].exists)
        // Borrowed logins don't write progress to that user's account.
        XCTAssertTrue(app.staticTexts["Progress saved locally"].exists)
    }

    func testWithoutAppleTVUsersInAppProfilesStay() {
        let app = XCUIApplication.launched(seed: "profiles", tab: "settings")
        XCTAssertTrue(app.staticTexts["Who's reading?"].waitForExistence(timeout: 10))
        select(app.element("profilePicker.Me"), .left)
        XCTAssertTrue(app.element("settings.switchProfile").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("settings.appleTVUser").exists)
    }
}
