import XCTest

final class ICloudSyncUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// CI builds have no iCloud container, so the screen explains why sync
    /// is off and the toggle can't be turned on.
    func testSyncIsOffWithAnExplanationWithoutICloud() {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.icloud"))
        let toggle = app.element("icloud.toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertFalse(toggle.isEnabled)
        let status = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Not set up", "Not set up")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), "status says sync isn't set up")
        XCTAssertTrue(app.element("icloud.explanation").exists)
        XCTAssertFalse(app.element("icloud.syncNow").exists)
    }

    func testWiFiBackupShowsAnAddress() {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.icloud"))
        XCTAssertTrue(app.element("icloud.toggle").waitForExistence(timeout: 10))
        select(app.element("icloud.backup"))
        let address = app.element("backup.address")
        let problem = app.element("backup.problem")
        let deadline = Date().addingTimeInterval(15)
        while !address.exists && !problem.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(address.exists || problem.exists, "the page starts or explains why not")
        if address.exists {
            XCTAssertTrue(address.label.hasPrefix("http://"), address.label)
            XCTAssertTrue(app.element("backup.qr").exists)
        }
    }
}
