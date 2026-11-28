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

    func testHomeShowsLatestSeriesAndOpensOne() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["shelf.newlyAdded"].waitForExistence(timeout: 20))
        let id = openFocusedPoster(app)
        let expected: [String: (String, Int)] = ["lantern": ("Lantern Courier", 2), "paper": ("Paper Moon Post", 1)]
        let key = String(id.split(separator: "/").last ?? "")
        let (name, count) = try XCTUnwrap(expected[key], "unexpected poster \(id)")
        XCTAssertEqual(app.staticTexts["series.title"].label, name)
        let chapters = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'chapter.c:'"))
        XCTAssertTrue(chapters.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(chapters.count, count)
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

        XCTAssertTrue(focus(app.element("serverEditor.test"), maxPresses: 16))
        XCUIRemote.shared.press(.select)
        let connected = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Connected to Test Catalog'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Latest series"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["All books"].exists)
    }

    func testAddServerOffersOPDS() {
        let app = launch(tab: "settings")
        select(app.element("settings.addServer"))
        XCTAssertTrue(app.buttons["OPDS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Calibre"].exists, "Calibre's content server has its own type")
    }
}
