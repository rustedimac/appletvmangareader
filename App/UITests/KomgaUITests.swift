import XCTest

/// Komga flows against `MockKomgaTransport` (launch flag `-mockKomga`), so
/// the real `KomgaClient` runs without a server.
final class KomgaUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockKomga"] + (tab.map { ["-uiTestingTab", $0] } ?? [])
        app.launch()
        return app
    }

    func testHomeShowsKomgaRowsAndOpensASeries() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["shelf.Test Komga.newlyAdded"].waitForExistence(timeout: 20))

        let poster = app.buttons["poster.s-lantern"]
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        select(poster)
        let title = app.staticTexts["series.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Lantern Courier")
        XCTAssertTrue(app.element("chapter.b-lantern-1").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("chapter.b-lantern-2").exists)
    }

    func testConnectionTestSignsIn() {
        let app = launch(tab: "settings")
        let row = app.element("settings.server.Test Komga")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        select(row)

        XCTAssertTrue(app.element("serverEditor.apiKey").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("serverEditor.username").exists, "email field")
        XCTAssertTrue(app.element("serverEditor.password").exists)
        XCTAssertTrue(app.element("serverEditor.save").isEnabled)

        select(app.element("serverEditor.test"))
        let signedIn = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Signed in to Komga'")).firstMatch
        XCTAssertTrue(signedIn.waitForExistence(timeout: 10))
        // Editing a server lists its libraries to import.
        XCTAssertTrue(app.element("categories.item.lib-manga").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("categories.item.lib-comics").exists)
    }

    func testAddServerOffersKomga() {
        let app = launch(tab: "settings")
        select(app.element("settings.addServer"))
        let komga = app.buttons["Komga"]
        XCTAssertTrue(komga.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Kavita"].exists)
        XCTAssertTrue(app.buttons["Suwayomi"].exists)
    }
}
