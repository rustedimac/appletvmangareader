import XCTest

/// Signing a profile in to Kavita with a username and password, and the
/// local Continue Reading row for a profile that doesn't sync to a
/// Suwayomi server. Runs against the offline demo servers; the demo Kavita
/// sign-in accepts reader / secret (see `AppModel+Demo.swift`).
final class ProgressSyncUITests: XCTestCase {
    var app: XCUIApplication!
    let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"] + extra
        app.launch()
    }

    /// Opens the full-screen keyboard for a field, types, and goes back.
    private func enter(_ text: String, into field: XCUIElement) {
        select(field)
        usleep(1_000_000)
        app.typeText(text)
        usleep(500_000)
        remote.press(.menu)
        usleep(1_000_000)
    }

    private func openDemoKavitaEditor() {
        let row = app.element("settings.server.Demo Kavita")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        select(row)
        XCTAssertTrue(app.element("serverEditor.username").waitForExistence(timeout: 5),
                      "a Kavita server with no login offers username and password")
        XCTAssertTrue(app.element("serverEditor.password").exists)
        XCTAssertFalse(app.element("serverEditor.apiKey").exists)
    }

    func testKavitaSignInWithUsernameAndPassword() {
        launch(["-uiTestingTab", "settings"])
        openDemoKavitaEditor()
        XCTAssertFalse(app.element("serverEditor.save").isEnabled, "needs a username and password")
        enter("reader", into: app.element("serverEditor.username"))
        enter("secret", into: app.element("serverEditor.password"))
        let save = app.element("serverEditor.save")
        XCTAssertTrue(save.isEnabled)
        select(save)

        // Back in Settings; the editor now shows who the profile is.
        let row = app.element("settings.server.Demo Kavita")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.element("serverEditor.save").exists)
        select(row)
        let footer = app.element("serverEditor.loginFooter")
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        XCTAssertTrue(footer.label.contains("Signed in as reader"), footer.label)
        // Unchanged, the saved login is kept without a password.
        XCTAssertTrue(app.element("serverEditor.save").isEnabled)
    }

    func testKavitaWrongPasswordShowsError() {
        launch(["-uiTestingTab", "settings"])
        openDemoKavitaEditor()
        enter("reader", into: app.element("serverEditor.username"))
        enter("nope", into: app.element("serverEditor.password"))
        select(app.element("serverEditor.save"))
        XCTAssertTrue(app.element("serverEditor.error").waitForExistence(timeout: 10),
                      "a rejected sign-in stays on the form with an error")
        XCTAssertTrue(app.element("serverEditor.save").exists)
    }

    func testProfileThatDoesNotSyncGetsLocalContinueReading() {
        // Two profiles: "Me" added the demo servers and syncs to Demo
        // Suwayomi; "Kid" keeps Suwayomi progress on the Apple TV.
        // Rows per server, so Demo Suwayomi's own Continue Reading row shows.
        launch(["-uiTestingSeed", "profiles", "-homePerServer"])
        XCTAssertTrue(app.staticTexts["Who's reading?"].waitForExistence(timeout: 10))
        select(app.element("profilePicker.Kid"), .right)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        // Home is lazy: Demo Suwayomi's rows sit below Demo Kavita's.
        XCTAssertTrue(scrollHome(to: app.staticTexts["shelf.Demo Suwayomi.recentlyUpdated"]))
        XCTAssertFalse(app.staticTexts["shelf.Demo Suwayomi.continueReading"].exists)

        // Library → Demo Suwayomi → a series → Start Reading → turn a page.
        selectTab("Library")
        let server = app.buttons["library.server.Demo Suwayomi"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: server, max: 4) || press(.right, until: server, max: 4))
        remote.press(.select)
        XCTAssertTrue(app.buttons["poster.1"].waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: focusedPoster, max: 4), "no poster took focus")
        remote.press(.select)
        let start = app.buttons["series.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.left, until: start, max: 3) || start.hasFocus)
        remote.press(.select)
        let reader = app.descendants(matching: .any)["reader.paged"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15), "reader didn't open")
        sleep(2)
        // Manga reads right to left: left is the next page.
        remote.press(.left)
        sleep(1)
        remote.press(.left)
        sleep(1)
        remote.press(.menu) // Closing the reader saves progress.
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor(start, "label BEGINSWITH 'Continue'"), "series should resume: \(start.label)")

        remote.press(.menu)
        selectTab("Home")
        XCTAssertTrue(scrollHome(to: app.staticTexts["shelf.Demo Suwayomi.continueReading"]),
                      "Kid's own Continue Reading row")
    }

    // MARK: Helpers

    /// Moves down Home's rows until `element` is loaded.
    private func scrollHome(to element: XCUIElement, maxPresses: Int = 10) -> Bool {
        let firstRow = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'shelf.'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15))
        for _ in 0..<maxPresses {
            if element.waitForExistence(timeout: 1.5) { return true }
            remote.press(.down)
        }
        return element.waitForExistence(timeout: 3)
    }

    private var focusedPoster: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let anyTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        if !anyTab.exists { press(.up, until: anyTab, max: 8) }
        XCTAssertTrue(anyTab.exists, "tab bar never took focus")
        if press(.right, until: tab, max: 6) { return }
        XCTAssertTrue(press(.left, until: tab, max: 6), "couldn't focus the \(name) tab")
    }
}
