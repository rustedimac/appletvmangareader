import XCTest

/// Home with two servers ("Demo Kavita" and "Demo Suwayomi", see
/// `SampleLibraryServer`): server feeds merged into one row each by
/// default, the "Row per Server" option, where posters name their server,
/// and the server + library line on series detail. Demo content is
/// generated ("Lantern Chronicles 3"); series whose id is a multiple of 3
/// are in both demo libraries ("All Series" and "Every Third").
final class HomeServerRowsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"] + extra
        app.launch()
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private var focusedPoster: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    }

    private func posters(labelEndingWith suffix: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND label ENDSWITH %@", suffix))
    }

    /// Caption lines under posters that mention `server`.
    private func captions(naming server: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(
            format: "(identifier BEGINSWITH 'poster.caption.' OR identifier BEGINSWITH 'poster.server.') AND label CONTAINS %@",
            server))
    }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format). Focus: \(focusedDescription())", file: file, line: line)
    }

    /// Moves focus toward `element` by comparing frames.
    @discardableResult
    private func moveFocus(to element: XCUIElement, maxPresses: Int = 40,
                           file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) doesn't exist", file: file, line: line)
        for _ in 0..<maxPresses {
            Thread.sleep(forTimeInterval: 0.3)
            if isFocused(element) { return true }
            let current = focused
            guard current.exists else { continue }
            let a = current.frame, b = element.frame
            if b.width == 0 || b.height == 0 { remote.press(.down) }
            else if b.midY > a.maxY { remote.press(.down) }
            else if b.midY < a.minY { remote.press(.up) }
            else if b.midX > a.midX { remote.press(.right) }
            else { remote.press(.left) }
        }
        let ok = isFocused(element)
        XCTAssertTrue(ok, "Couldn't focus \(element). Focus: \(focusedDescription())", file: file, line: line)
        return ok
    }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        let anyTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where !anyTab.exists {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(anyTab.exists, "tab bar never took focus")
        moveFocus(to: tab, maxPresses: 8)
    }

    private func openCustomizeHome() {
        selectTab("Settings")
        if app.buttons["homeLayout.serverRows.merged"].waitForExistence(timeout: 2) { return }
        let link = app.buttons["settings.customizeHome"]
        moveFocus(to: link)
        remote.press(.select)
        XCTAssertTrue(app.buttons["homeLayout.serverRows.merged"].waitForExistence(timeout: 10))
    }

    private func choose(_ id: String) {
        let button = app.buttons[id]
        moveFocus(to: button)
        remote.press(.select)
        wait(button, "value == 'selected'")
    }

    // MARK: Tests

    func testServersMergeIntoOneRowPerFeedByDefault() {
        launch()
        let row = app.staticTexts["shelf.recentlyUpdated"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no merged Recently Updated row")
        XCTAssertEqual(row.label, "Recently Updated", "a merged row doesn't name a server")
        XCTAssertFalse(app.staticTexts["shelf.Demo Kavita.recentlyUpdated"].exists)
        XCTAssertFalse(app.staticTexts["shelf.Demo Suwayomi.recentlyUpdated"].exists)
        XCTAssertTrue(app.staticTexts["shelf.newlyAdded"].exists)

        // Both servers' series are in the row, and each poster names its server.
        XCTAssertTrue(posters(labelEndingWith: ", Demo Kavita").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(posters(labelEndingWith: ", Demo Suwayomi").firstMatch.exists)
        XCTAssertTrue(captions(naming: "Demo Suwayomi").firstMatch.exists, "server name under the title")
        let caption = captions(naming: "Demo Kavita").firstMatch
        XCTAssertTrue(caption.exists)
        XCTAssertTrue(caption.label.contains(" · Demo Kavita"),
                      "the server shares the caption's line: \(caption.label)")
    }

    func testRowPerServerOption() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        openCustomizeHome()
        XCTAssertEqual(app.buttons["homeLayout.serverRows.merged"].value as? String, "selected", "merged is the default")
        choose("homeLayout.serverRows.perServer")

        selectTab("Home")
        let kavita = app.staticTexts["shelf.Demo Kavita.recentlyUpdated"]
        XCTAssertTrue(kavita.waitForExistence(timeout: 15))
        XCTAssertEqual(kavita.label, "Recently Updated · Demo Kavita")
        XCTAssertTrue(app.staticTexts["shelf.Demo Suwayomi.recentlyUpdated"].exists)
        XCTAssertFalse(app.staticTexts["shelf.recentlyUpdated"].exists)

        openCustomizeHome()
        choose("homeLayout.serverRows.merged")
        selectTab("Home")
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertFalse(kavita.exists)
    }

    func testServerNameOnCoverThenOff() {
        launch(["-posterServerLabel", "onCover"])
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertTrue(posters(labelEndingWith: ", Demo Kavita").firstMatch.waitForExistence(timeout: 5),
                      "the poster still says which server")
        XCTAssertFalse(captions(naming: "Demo Kavita").firstMatch.exists, "not under the title too")

        openCustomizeHome()
        XCTAssertEqual(app.buttons["homeLayout.serverLabel.onCover"].value as? String, "selected")
        choose("homeLayout.serverLabel.off")
        selectTab("Home")
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.'")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertFalse(posters(labelEndingWith: ", Demo Kavita").firstMatch.exists)
        XCTAssertFalse(posters(labelEndingWith: ", Demo Suwayomi").firstMatch.exists)
        XCTAssertFalse(captions(naming: "Demo").firstMatch.exists)
    }

    func testSeriesDetailShowsServerAndLibraries() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        for _ in 0..<6 where !focusedPoster.exists {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(focusedPoster.exists, "no poster took focus")
        let id = Int(focusedPoster.identifier.dropFirst("poster.".count)) ?? 0
        let server = focusedPoster.label.hasSuffix(", Demo Suwayomi") ? "Demo Suwayomi" : "Demo Kavita"
        XCTAssertGreaterThan(id, 0)
        remote.press(.select)

        let location = app.descendants(matching: .any)["series.location"]
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        // Every third series is in both demo libraries.
        let expected = "\(server) · All Series" + (id % 3 == 0 ? ", Every Third" : "")
        wait(location, "label == '\(expected)'")
    }
}
