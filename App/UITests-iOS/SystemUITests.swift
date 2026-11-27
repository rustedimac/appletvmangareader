import XCTest

/// iPhone/iPad system pieces (docs/IOS.md §1, step 4): backup through Files,
/// no "Set Up from Your Phone", no remote help.
final class SystemUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingTab", "settings"]
        app.launch()
        return app
    }

    /// Scrolls until the element is on screen (forms load rows lazily).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func testBackupUsesFiles() {
        let app = launchSettings()
        XCTAssertTrue(app.buttons["settings.addServer"].waitForExistence(timeout: 10))
        let icloud = app.buttons["settings.icloud"]
        reveal(icloud, in: app)
        XCTAssertTrue(icloud.exists, "No iCloud row:\n\(app.debugDescription)")
        icloud.tap()
        let backup = app.buttons["icloud.backup"]
        _ = backup.waitForExistence(timeout: 3)
        reveal(backup, in: app)
        XCTAssertTrue(backup.exists, "No backup row:\n\(app.debugDescription)")
        backup.tap()
        XCTAssertTrue(app.buttons["backup.export"].waitForExistence(timeout: 5), "No Export Backup:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["backup.import"].exists)
        app.buttons["backup.export"].tap()
        // The system's save sheet opens (its own process); the app stays up.
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testNoPhoneSetupOrRemoteHelp() {
        let app = launchSettings()
        XCTAssertTrue(app.buttons["settings.addServer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.controls"].exists, "Remote help shouldn't show on iOS")
        let add = app.buttons["settings.addServer"]
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertFalse(app.buttons["serverEditor.phoneSetup"].exists, "Phone setup shouldn't show on iOS")
    }
}
