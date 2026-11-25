import XCTest

/// Home, Library and Search pick up server, library and poster size
/// changes right away, without relaunching the app. Runs against the offline demo servers
/// ("Demo Kavita" and "Demo Suwayomi", see `SampleLibraryServer`), whose
/// libraries are "all" (every series) and "short" (every third series).
final class ContentRefreshUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"]
        app.launch()
    }

    // MARK: Helpers

    /// One Home shelf (title and posters), so posters can be matched per
    /// server: both demo servers use the same series ids.
    private func shelf(_ identifier: String) -> XCUIElement {
        app.element("shelfRow.\(identifier)")
    }

    private func poster(_ id: String, in shelf: XCUIElement) -> XCUIElement {
        shelf.descendants(matching: .any).matching(identifier: "poster.\(id)").firstMatch
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

    /// Opens a text field's keyboard, types, and goes back to the form.
    private func enter(_ text: String, into id: String) {
        select(app.element(id))
        usleep(800_000)
        app.typeText(text)
        remote.press(.menu)
        usleep(800_000)
    }

    // MARK: Tests

    func testUntickingALibraryUpdatesHomeWithoutRelaunch() {
        // Demo Suwayomi needs no login, so its editor lists categories.
        let kavita = shelf("Demo Kavita.recentlyUpdated")
        let suwayomi = shelf("Demo Suwayomi.recentlyUpdated")
        XCTAssertTrue(suwayomi.waitForExistence(timeout: 15))
        XCTAssertTrue(poster("89", in: suwayomi).waitForExistence(timeout: 10), "series 89 is in All Series")

        // Import only "Every Third" from Demo Suwayomi.
        selectTab("Settings")
        select(app.element("settings.server.Demo Suwayomi"))
        let all = app.element("categories.item.all")
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        select(all)
        XCTAssertTrue(waitUntil(all, "value == 'off'"))
        select(app.element("serverEditor.save"))
        XCTAssertTrue(app.element("settings.server.Demo Suwayomi").waitForExistence(timeout: 10))

        selectTab("Home")
        XCTAssertTrue(suwayomi.waitForExistence(timeout: 15))
        XCTAssertTrue(poster("87", in: suwayomi).waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(poster("89", in: suwayomi), "exists == false", timeout: 15),
                      "Home still shows a series from the unticked category")
        XCTAssertTrue(poster("89", in: kavita).exists, "the other server is unchanged")

        // Search follows the same selection.
        selectTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        remote.press(.down)
        usleep(500_000)
        field.typeText("Chronicles 89")
        XCTAssertTrue(app.staticTexts["shelf.search.Demo Kavita"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["shelf.search.Demo Suwayomi"].exists,
                       "Search still finds a series from the unticked category")
    }

    func testPosterSizeChangesHomeShelvesRightAway() {
        let kavita = shelf("Demo Kavita.recentlyUpdated")
        XCTAssertTrue(kavita.waitForExistence(timeout: 15))
        let before = poster("89", in: kavita)
        XCTAssertTrue(before.waitForExistence(timeout: 10))
        let medium = before.frame.width

        selectTab("Settings")
        let link = app.element("settings.customizeHome")
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        if focus(link, .down, maxPresses: 25) { remote.press(.select) }
        let large = app.element("browse.density.large")
        XCTAssertTrue(large.waitForExistence(timeout: 10))
        // The sizes sit side by side: down to Medium, then right to Large.
        focus(app.element("browse.density.standard"), .down, maxPresses: 25)
        if focus(large, .right, maxPresses: 4) { remote.press(.select) }
        XCTAssertTrue(waitUntil(large, "value == 'selected'"))

        selectTab("Home")
        let after = poster("89", in: kavita)
        XCTAssertTrue(after.waitForExistence(timeout: 15))
        var width = after.frame.width
        for _ in 0..<20 where width < medium + 40 {
            usleep(500_000)
            width = after.frame.width
        }
        XCTAssertGreaterThan(width, medium + 40, "Home posters kept their old size (\(width) vs \(medium))")
    }

    func testAddedServerShowsOnHomeWithoutRelaunch() {
        XCTAssertTrue(shelf("Demo Kavita.recentlyUpdated").waitForExistence(timeout: 15))

        selectTab("Settings")
        select(app.element("settings.addServer"))
        XCTAssertTrue(app.element("serverEditor.address").waitForExistence(timeout: 10))
        enter("Harbor Shelf", into: "serverEditor.name")
        enter("https://harbor.invalid", into: "serverEditor.address")
        enter("demo-key", into: "serverEditor.apiKey")
        let save = app.element("serverEditor.save")
        XCTAssertTrue(waitUntil(save, "isEnabled == true"), "address and key typed")
        select(save)
        XCTAssertTrue(app.element("settings.server.Harbor Shelf").waitForExistence(timeout: 10))

        selectTab("Home")
        // Home is a lazy stack and the new server's shelf comes third, below
        // the screen: scroll down to it.
        let harbor = shelf("Harbor Shelf.recentlyUpdated")
        XCTAssertTrue(app.element("shelfRow.Demo Kavita.recentlyUpdated").waitForExistence(timeout: 15))
        for _ in 0..<8 where !harbor.waitForExistence(timeout: 2) {
            remote.press(.down)
        }
        XCTAssertTrue(harbor.waitForExistence(timeout: 5), "the new server's rows show up without relaunching")
        XCTAssertTrue(shelf("Demo Kavita.recentlyUpdated").exists)
    }
}
