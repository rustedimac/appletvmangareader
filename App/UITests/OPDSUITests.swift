import XCTest

/// OPDS flows against `MockOPDSTransport` (launch flag `-mockOPDS`), so the
/// real `OPDSClient` runs without a server.
final class OPDSUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockOPDS"] + (tab.map { ["-uiTestingTab", $0] } ?? [])
        app.launch()
        return app
    }

    func testHomeShowsLatestSeriesAndOpensOne() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["shelf.Test OPDS.newlyAdded"].waitForExistence(timeout: 20))
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.f:'")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        select(poster)
        let title = app.staticTexts["series.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Lantern Courier")
        let chapters = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'chapter.c:'"))
        XCTAssertTrue(chapters.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(chapters.count, 2)
    }

    func testEditorFindsTheCatalogAndHasNoSyncToggle() {
        let app = launch(tab: "settings")
        let row = app.element("settings.server.Test OPDS")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        select(row)
        XCTAssertTrue(app.element("serverEditor.username").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("serverEditor.password").exists)
        XCTAssertFalse(app.element("serverEditor.sync").exists, "OPDS keeps progress on the Apple TV")
        XCTAssertTrue(app.element("serverEditor.save").isEnabled)

        select(app.element("serverEditor.test"))
        let connected = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Connected to Test Catalog'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Latest series"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["All books"].exists)
    }

    func testAddServerOffersOPDS() {
        let app = launch(tab: "settings")
        select(app.element("settings.addServer"))
        XCTAssertTrue(app.buttons["OPDS"].waitForExistence(timeout: 5))
    }
}
