import XCTest

/// Browsing flows against the offline demo servers ("Demo Kavita" and
/// "Demo Suwayomi", see `DemoMangaServer`). Driven with the Siri Remote,
/// since tvOS has no taps.
final class BrowseUITests: XCTestCase {
    var app: XCUIApplication!
    let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"]
        app.launch()
    }

    // MARK: Helpers

    private var focusedPoster: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Presses `direction` until `element` has focus.
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

    /// From Home, moves focus down to a poster and opens it. Returns the
    /// series id (the tab bar is centered, so which poster gets focus
    /// depends on the layout).
    @discardableResult
    private func openFirstHomeSeries() -> String {
        XCTAssertTrue(app.staticTexts["shelf.Demo Kavita.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertTrue(press(.down, until: focusedPoster, max: 6), "no poster took focus")
        let id = String(focusedPoster.identifier.dropFirst("poster.".count))
        XCTAssertFalse(id.isEmpty)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10))
        return id
    }

    // MARK: Tests

    func testHomeShowsRowsForEachServer() {
        XCTAssertTrue(app.staticTexts["shelf.Demo Kavita.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["shelf.Demo Kavita.newlyAdded"].exists)
        XCTAssertTrue(app.staticTexts["home.server.Demo Kavita"].exists)
        XCTAssertFalse(app.staticTexts["shelf.favorites"].exists, "no favorites yet")
    }

    func testFavoriteFromDetailShowsOnHomeAndFavoritesTab() {
        let id = openFirstHomeSeries()
        let start = app.buttons["series.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.label, "Start Reading")

        let favorite = app.buttons["series.favorite"]
        XCTAssertEqual(favorite.value as? String, "off")
        XCTAssertTrue(press(.right, until: favorite, max: 3))
        remote.press(.select)
        XCTAssertTrue(waitFor(favorite, "value == 'on'"))

        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["shelf.favorites"].waitForExistence(timeout: 10))

        selectTab("Favorites")
        XCTAssertTrue(app.buttons["poster.\(id)"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No favorites yet"].exists)
    }

    func testChapterListAndStartOpensReader() {
        let id = openFirstHomeSeries()
        let first = app.buttons["chapter.\(id)-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertEqual(first.value as? String, "unread")

        let start = app.buttons["series.continue"]
        XCTAssertTrue(press(.left, until: start, max: 3), "Start should be focusable")
        remote.press(.select)
        XCTAssertTrue(app.otherElements["reader.placeholder"].waitForExistence(timeout: 10))
        remote.press(.menu)
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["reader.placeholder"].exists)
    }

    func testLibraryCategoriesAndPaging() {
        selectTab("Library")
        let server = app.buttons["library.server.Demo Kavita"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: server, max: 4))
        remote.press(.select)

        XCTAssertTrue(app.buttons["category.all"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["category.short"].exists)
        XCTAssertTrue(app.buttons["poster.1"].waitForExistence(timeout: 10))
        let secondPage = app.buttons.matching(NSPredicate(format: "identifier IN %@", (49...90).map { "poster.\($0)" })).firstMatch

        // Scroll down through the grid; the second page (49 and up) loads on the way.
        for _ in 0..<14 {
            remote.press(.down)
            usleep(400_000)
        }
        XCTAssertTrue(secondPage.waitForExistence(timeout: 10), "second page never loaded")

        // Switching category replaces the grid.
        remote.press(.up)
        XCTAssertTrue(press(.up, until: app.buttons["category.all"], max: 24))
        XCTAssertTrue(press(.right, until: app.buttons["category.short"], max: 2))
        remote.press(.select)
        XCTAssertTrue(waitFor(app.buttons["category.short"], "value == 'selected'"))
        XCTAssertTrue(app.buttons["poster.3"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["poster.1"].exists)
    }

    func testSearchGroupsResultsByServer() {
        selectTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        remote.press(.down)
        usleep(500_000)
        field.typeText("Lantern")
        XCTAssertTrue(app.staticTexts["shelf.search.Demo Kavita"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["shelf.search.Demo Suwayomi"].exists)
    }
}
