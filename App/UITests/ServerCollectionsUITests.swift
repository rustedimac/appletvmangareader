import XCTest

/// Reading lists, collections and smart filters on the offline demo
/// servers (`SampleLibraryServer+Collections`): Demo Kavita has one of
/// each (plus an empty reading list), Demo Suwayomi none.
final class ServerCollectionsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"]
        app.launch()
    }

    private func waitFor(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 10) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func press(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if element.exists && isFocused(element) { return true }
            remote.press(direction)
            usleep(350_000)
        }
        return element.exists && isFocused(element)
    }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let anyTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        if !anyTab.exists { _ = press(.up, until: anyTab, max: 8) }
        XCTAssertTrue(anyTab.exists, "tab bar never took focus")
        if press(.right, until: tab, max: 6) { return }
        XCTAssertTrue(press(.left, until: tab, max: 6), "couldn't focus the \(name) tab")
    }

    /// Library tab → a demo server → its category bar.
    private func openServer(_ name: String) {
        selectTab("Library")
        let server = app.buttons["library.server.\(name)"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: server, max: 4))
        remote.press(.select)
        XCTAssertTrue(app.buttons["category.all"].waitForExistence(timeout: 10))
    }

    /// Focuses a button in the category bar (it sits right of the
    /// categories) and opens it.
    private func openBarButton(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(id) missing")
        if !press(.right, until: button, max: 10) {
            XCTAssertTrue(press(.left, until: button, max: 10), "couldn't focus \(id). Focus: \(focusedDescription())")
        }
        remote.press(.select)
    }

    func testReadingListShowsChaptersInOrderAndOpensTheReader() {
        openServer("Demo Kavita")
        openBarButton("library.collections.readingList")
        XCTAssertTrue(app.staticTexts["collections.title"].waitForExistence(timeout: 10))
        let list = app.buttons["collection.rl-1"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["collection.rl-2"].exists)
        XCTAssertTrue(press(.down, until: list, max: 4), "list poster never took focus")
        remote.press(.select)

        XCTAssertTrue(app.staticTexts["collection.title"].waitForExistence(timeout: 10))
        let entries = (0..<4).map { app.buttons["readingList.entry.rl-1-\($0)"] }
        XCTAssertTrue(entries[0].waitForExistence(timeout: 10))
        // List order, not series order: series 1, 2, 3, then 1 again.
        let tops = entries.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "entries out of order")
        XCTAssertEqual(entries[0].value as? String, "unread")

        let start = app.buttons["readingList.continue"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(waitFor(start, "hasFocus == true") || press(.up, until: start, max: 6), "Start should take focus")
        remote.press(.select)
        let reader = app.descendants(matching: .any)["reader.paged"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15), "reader didn't open")
        remote.press(.menu)
        XCTAssertTrue(waitFor(reader, "exists == false"), "reader didn't close")
        XCTAssertTrue(start.waitForExistence(timeout: 10))

        // A row's "…" goes to the series.
        let series = app.buttons["readingList.series.rl-1-1"]
        XCTAssertTrue(press(.down, until: entries[1], max: 4))
        XCTAssertTrue(press(.right, until: series, max: 2))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["series.title"].label, "Harbor Chronicles 2")
    }

    func testCollectionAndSmartFilterShowTheirSeries() {
        openServer("Demo Kavita")
        openBarButton("library.collections.collection")
        let collection = app.buttons["collection.c-1"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: collection, max: 4))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["collection.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["poster.2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["poster.10"].exists)
        XCTAssertFalse(app.buttons["poster.1"].exists)

        remote.press(.menu)
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        remote.press(.menu)
        openBarButton("library.collections.smartFilter")
        let filter = app.buttons["collection.sf-1"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: filter, max: 4))
        remote.press(.select)
        XCTAssertTrue(app.buttons["poster.5"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["poster.10"].exists)
        XCTAssertFalse(app.buttons["poster.2"].exists)
    }

    func testEmptyListAndServersWithoutLists() {
        openServer("Demo Kavita")
        openBarButton("library.collections.readingList")
        let empty = app.buttons["collection.rl-2"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: empty, max: 4) || press(.right, until: empty, max: 4))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["This list is empty"].waitForExistence(timeout: 10))

        // Demo Suwayomi offers none, so its bar has no list buttons.
        remote.press(.menu)
        remote.press(.menu)
        remote.press(.menu)
        let suwayomi = app.buttons["library.server.Demo Suwayomi"]
        XCTAssertTrue(suwayomi.waitForExistence(timeout: 10))
        XCTAssertTrue(press(.down, until: suwayomi, max: 4))
        remote.press(.select)
        XCTAssertTrue(app.buttons["category.all"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["library.collections.readingList"].exists)
        XCTAssertFalse(app.buttons["library.collections.collection"].exists)
    }
}
