import XCTest

final class ProfilesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSingleProfileSkipsPicker() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Who's reading?"].exists)
    }

    func testPickerShowsAtLaunchWithTwoProfiles() {
        let app = XCUIApplication.launched(seed: "profiles", tab: "settings")
        XCTAssertTrue(app.staticTexts["Who's reading?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("profilePicker.Me").exists)
        let kid = app.element("profilePicker.Kid")
        select(kid, .right)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        // Settings shows the newly active profile.
        XCTAssertTrue(app.staticTexts["Kid"].waitForExistence(timeout: 5))
    }

    func testAddProfileThenSwitch() {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.manageProfiles"))
        select(app.element("profiles.add"))
        // The name is prefilled, so no typing is needed.
        // A new profile is created with "Add Profile" (the only button besides Delete).
        select(app.element("profileEditor.add"))
        XCTAssertTrue(app.element("profiles.row.Profile 2").waitForExistence(timeout: 5))

        XCUIRemote.shared.press(.menu)
        select(app.element("settings.switchProfile"), .up)
        XCTAssertTrue(app.staticTexts["Who's reading?"].waitForExistence(timeout: 5))
        select(app.element("profilePicker.Profile 2"), .right)
        XCTAssertTrue(app.staticTexts["Profile 2"].waitForExistence(timeout: 5))
    }

    func testDeleteProfile() {
        let app = XCUIApplication.launched(seed: "profiles", tab: "settings")
        select(app.element("profilePicker.Me"), .left)
        select(app.element("settings.manageProfiles"))
        select(app.element("profiles.row.Kid"))
        select(app.element("profileEditor.delete"))
        select(app.element("profileEditor.confirmDelete"), .right)
        XCTAssertTrue(app.element("profiles.row.Me").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("profiles.row.Kid").exists)
    }
}
