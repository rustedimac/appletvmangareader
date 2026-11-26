import XCTest

/// Profile PINs and content filters. Seeds are in `UITestingSeed`:
/// "pins" has Me (PIN 1111, asked on open) and Kid (PIN 3333, Horror
/// hidden); "filtered" hides Horror (every fifth demo series).
final class ContentFilterUITests: XCTestCase {
    let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + args
        app.launch()
        return app
    }

    /// Enters four of the same digit on the keypad.
    private func enter(_ digit: Int, in app: XCUIApplication, from direction: XCUIRemote.Button = .right) {
        let key = app.element("pin.key.\(digit)")
        XCTAssertTrue(focus(key, direction))
        for _ in 0..<4 {
            remote.press(.select)
            usleep(300_000)
        }
    }

    func testProfileWithPINAsksBeforeOpening() {
        let app = launch(["-uiTestingSeed", "pins", "-uiTestingTab", "settings"])
        XCTAssertTrue(app.staticTexts["Who's reading?"].waitForExistence(timeout: 10))
        select(app.element("profilePicker.Me"), .left)
        let title = app.element("pin.title")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Enter Me's PIN")

        enter(2, in: app)
        let message = app.element("pin.message")
        XCTAssertTrue(waitUntil(message, "label BEGINSWITH 'Wrong PIN'"), "wrong PIN wasn't rejected")
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)

        enter(1, in: app, from: .left)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10), "right PIN didn't open the profile")
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 5))
    }

    func testKidOpensFreelyButContentSettingsNeedThePIN() {
        let app = launch(["-uiTestingSeed", "pins", "-uiTestingTab", "settings"])
        select(app.element("profilePicker.Kid"), .right)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10), "Kid should open without a PIN")

        select(app.element("settings.content"))
        let title = app.element("pin.title")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Enter Kid's PIN")
        enter(3, in: app)

        let horror = app.element("content.genre.Horror")
        XCTAssertTrue(horror.waitForExistence(timeout: 10), "content settings didn't open")
        XCTAssertEqual(horror.value as? String, "hidden")
        XCTAssertTrue(app.element("content.changePIN").exists)
    }

    func testSetPINOnProfileWithoutOne() {
        let app = launch(["-uiTestingTab", "settings"])
        select(app.element("settings.content"))
        select(app.element("content.setPIN"))
        XCTAssertTrue(app.element("pin.title").waitForExistence(timeout: 10))
        enter(1, in: app)
        XCTAssertTrue(waitUntil(app.element("pin.title"), "label == 'Enter it again'"))
        enter(1, in: app)
        XCTAssertTrue(app.element("content.changePIN").waitForExistence(timeout: 10), "PIN wasn't saved")
        XCTAssertTrue(app.element("content.requirePIN").exists)
        XCTAssertEqual(app.element("content.requirePIN").value as? String, "off")
    }

    func testHiddenGenreLeavesSearchResults() {
        let app = launch(["-demoServers", "-uiTestingSeed", "filtered", "-uiTestingTab", "search"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        remote.press(.down)
        usleep(500_000)
        field.typeText("Lantern")
        // 11 demo series match "Lantern"; 35 and 75 are Horror.
        let kavita = app.staticTexts["shelf.search.Demo Kavita"]
        XCTAssertTrue(kavita.waitForExistence(timeout: 15))
        XCTAssertEqual(kavita.label, "Demo Kavita (9)")
        XCTAssertEqual(app.staticTexts["shelf.search.Demo Suwayomi"].label, "Demo Suwayomi (9)")
        XCTAssertFalse(app.buttons["poster.35"].exists)
    }

    func testHidingAGenreInSettings() {
        let app = launch(["-demoServers", "-uiTestingTab", "settings"])
        select(app.element("settings.content"))
        let horror = app.element("content.genre.Horror")
        XCTAssertTrue(horror.waitForExistence(timeout: 15), "demo genres didn't load")
        XCTAssertEqual(horror.value as? String, "shown")
        XCTAssertTrue(app.element("content.age.none").exists, "demo Kavita offers age limits")
        if focus(horror, .down, maxPresses: 30) { remote.press(.select) }
        XCTAssertTrue(waitUntil(horror, "value == 'hidden'"))
    }
}
