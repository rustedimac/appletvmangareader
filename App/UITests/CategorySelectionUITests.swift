import XCTest

/// Picking which libraries/categories to import, against the offline demo
/// servers. Their categories are "all" (All Series) and "short" (Every Third).
final class CategorySelectionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers", "-uiTestingTab", tab]
        app.launch()
        return app
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func testServerEditorListsCategoriesAndSavesTicks() {
        let app = launch(tab: "settings")
        select(app.element("settings.server.Demo Suwayomi"))

        // Editing a saved server loads its categories right away, all ticked.
        let all = app.element("categories.item.all")
        let short = app.element("categories.item.short")
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        XCTAssertEqual(all.value as? String, "on")
        XCTAssertEqual(short.value as? String, "on")

        XCTAssertTrue(focus(short, maxPresses: 16))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil(short, "value == 'off'"))

        // A connection test keeps the ticks.
        XCTAssertTrue(focus(app.element("serverEditor.test"), maxPresses: 16))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(short.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(short, "value == 'off'"))

        XCTAssertTrue(focus(app.element("serverEditor.save"), maxPresses: 16))
        XCUIRemote.shared.press(.select)
        let row = app.element("settings.server.Demo Suwayomi")
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // Reopening shows the saved choice.
        select(row)
        XCTAssertTrue(short.waitForExistence(timeout: 10))
        XCTAssertEqual(short.value as? String, "off")
        XCTAssertEqual(all.value as? String, "on")
    }

    func testCannotSaveWithNothingTicked() {
        let app = launch(tab: "settings")
        select(app.element("settings.server.Demo Suwayomi"))
        let toggleAll = app.element("categories.toggleAll")
        XCTAssertTrue(toggleAll.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(toggleAll, maxPresses: 16))
        XCUIRemote.shared.press(.select) // "Select None"
        XCTAssertTrue(waitUntil(app.element("categories.item.all"), "value == 'off'"))
        XCTAssertFalse(app.element("serverEditor.save").isEnabled)
        select(toggleAll) // "Select All"
        XCTAssertTrue(waitUntil(app.element("serverEditor.save"), "isEnabled == true"))
    }

    func testLibraryTabPickerHidesUntickedCategory() {
        let app = launch(tab: "library")
        select(app.element("library.server.Demo Kavita"))
        XCTAssertTrue(app.element("category.all").waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("category.short").exists)

        select(app.element("library.chooseCategories"), .right)
        let all = app.element("categories.item.all")
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        select(all)
        XCTAssertTrue(waitUntil(all, "value == 'off'"))
        select(app.element("categories.save"))

        XCTAssertTrue(app.element("category.short").waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilGone(app.element("category.all")), "the unticked library is still listed")
    }
}

/// Waits for `predicate` (NSPredicate format) to hold for `element`.
func waitUntil(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 10) -> Bool {
    let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
}
