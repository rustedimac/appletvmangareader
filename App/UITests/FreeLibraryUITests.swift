import XCTest

/// The built-in Free Library, launched with `-uiTesting -freeLibrary`: the
/// bundled catalog plus canned IIIF manifests and Pepper&Carrot episodes
/// (`FreeLibraryDemoTransport`), so no test depends on archive.org.
final class FreeLibraryUITests: XCTestCase {
    var app: XCUIApplication!
    let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(tab: String? = nil) {
        var args = ["-uiTesting", "-freeLibrary"]
        if let tab { args += ["-uiTestingTab", tab] }
        app.launchArguments = args
        app.launch()
    }

    private var focusedPoster: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    }

    @discardableResult
    private func press(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            usleep(350_000)
        }
        return element.exists && element.hasFocus
    }

    func testHomeShowsFreeLibraryWithoutSetup() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.newlyAdded"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["No servers yet"].exists)
    }

    func testOpenSeriesShowsCreditAndOpensReader() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.newlyAdded"].waitForExistence(timeout: 15))
        XCTAssertTrue(press(.down, until: focusedPoster, max: 6), "no poster took focus")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10))
        let synopsis = app.staticTexts["series.synopsis"]
        XCTAssertTrue(synopsis.waitForExistence(timeout: 10))
        let text = synopsis.label
        XCTAssertTrue(text.contains("Internet Archive") || text.contains("David Revoy"),
                      "credit missing from: \(text)")

        let start = app.buttons["series.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.up, until: start, max: 4) || press(.down, until: start, max: 4))
        remote.press(.select)
        XCTAssertTrue(app.element("reader.paged").waitForExistence(timeout: 15), "reader didn't open")
        XCTAssertFalse(app.element("reader.error").exists)
    }

    func testSettingsShowsCreditsAndCanRemoveAndRestore() {
        launch(tab: "settings")
        let row = app.element("settings.server.Free Library")
        select(row)
        XCTAssertTrue(app.element("freeLibrary.about").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("freeLibrary.credit.0").exists)
        XCTAssertTrue(app.element("freeLibrary.credit.0").label.contains("David Revoy"))

        select(app.element("freeLibrary.remove"))
        let confirm = app.buttons["freeLibrary.confirmRemove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        select(confirm, .right)

        let add = app.element("settings.addFreeLibrary")
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertFalse(app.element("settings.server.Free Library").exists)
        select(add, .up)
        XCTAssertTrue(app.element("settings.server.Free Library").waitForExistence(timeout: 10))
    }

    func testAddServerDoesNotOfferFreeLibrary() {
        launch(tab: "settings")
        select(app.element("settings.addServer"))
        let picker = app.element("serverEditor.kind")
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Kavita"].exists)
        XCTAssertFalse(picker.buttons["Free Library"].exists)
    }
}
