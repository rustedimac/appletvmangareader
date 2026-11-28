import XCTest

/// The first-run welcome. It only shows in UI tests with `-welcome`; with
/// no `-freeLibrary` the install starts empty and the offline Free Library
/// client is ready for "Start Reading".
final class WelcomeUITests: XCTestCase {
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = [], tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-uiTesting", "-welcome"] + extra
        if let tab { args += ["-uiTestingTab", tab] }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    /// Empty install: the suggested collections are ticked, the picks
    /// change, and the Library then holds exactly what was ticked.
    func testEmptyInstallPicksCollectionsThenShowsThem() {
        let app = launch(tab: "library")
        let start = app.element("welcome.start")
        XCTAssertTrue(start.waitForExistence(timeout: 10), "no welcome on an empty install")
        let explanation = app.element("welcome.explanation")
        XCTAssertTrue(explanation.exists)
        XCTAssertEqual(explanation.elementType, .staticText, "the intro must be plain text, not a button")
        XCTAssertFalse(explanation.hasFocus, "the intro must not take focus")

        let comics = app.element("welcome.collection.comics")
        let pulps = app.element("welcome.collection.pulps")
        XCTAssertEqual(value(comics), "on")
        XCTAssertEqual(value(app.element("welcome.collection.webcomics")), "on")
        XCTAssertEqual(value(pulps), "off")
        XCTAssertEqual(value(app.element("welcome.collection.books")), "off")

        select(pulps)
        XCTAssertTrue(waitFor(pulps, value: "on"), "pulps didn't tick")
        select(comics, .up)
        XCTAssertTrue(waitFor(comics, value: "off"), "comics didn't untick")

        select(start)
        XCTAssertTrue(waitUntilGone(start), "welcome stayed after Start Reading")
        XCTAssertTrue(app.element("category.pulps").waitForExistence(timeout: 15), "picked collection missing")
        XCTAssertTrue(app.element("category.webcomics").exists)
        XCTAssertFalse(app.element("category.comics").exists, "unticked collection is listed")
    }

    /// The Free Library is there but this profile never picked: Start
    /// Reading lands on Home with the Free Library, and removing every
    /// library brings the welcome back.
    func testStartReadingShowsHomeAndWelcomeReturnsWhenEverythingIsRemoved() {
        let app = launch(["-freeLibrary"], tab: "settings")
        let start = app.element("welcome.start")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        select(start)
        XCTAssertTrue(waitUntilGone(start))

        select(app.element("settings.server.Free Library"))
        select(app.element("freeLibrary.remove"))
        let confirm = app.buttons["freeLibrary.confirmRemove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        select(confirm, .right)
        XCTAssertTrue(start.waitForExistence(timeout: 10), "welcome didn't come back with no libraries left")
        XCTAssertEqual(value(app.element("welcome.collection.comics")), "on")
    }

    func testNeverShownWhenServersExist() {
        let app = launch(["-uiTestingSeed", "servers"])
        // The seeded servers don't exist, so Home only shows error rows;
        // the tab bar is the reliable sign the tabs are up.
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15), "the tabs didn't show")
        XCTAssertFalse(app.element("welcome.start").exists)
    }

    func testFreeLibraryHomeAfterStartReading() {
        let app = launch(["-freeLibrary"])
        let start = app.element("welcome.start")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        select(start)
        XCTAssertTrue(app.staticTexts["shelf.newlyAdded"].waitForExistence(timeout: 15), "Home has no Free Library row")
    }

    func testOtherWaysToStartOpenAndComeBack() {
        let app = launch()
        XCTAssertTrue(app.element("welcome.start").waitForExistence(timeout: 10))

        select(app.element("welcome.addServer"))
        XCTAssertTrue(app.element("serverEditor.address").waitForExistence(timeout: 10), "server editor didn't open")
        remote.press(.menu)
        XCTAssertTrue(app.element("welcome.restore").waitForExistence(timeout: 10))

        select(app.element("welcome.restore"))
        let address = app.element("backup.address"), problem = app.element("backup.problem")
        let opened = address.waitForExistence(timeout: 10) || problem.exists
        XCTAssertTrue(opened, "backup page didn't open")
        remote.press(.menu)
        XCTAssertTrue(app.element("welcome.start").waitForExistence(timeout: 10))
    }

    private func waitFor(_ element: XCUIElement, value expected: String, timeout: TimeInterval = 5) -> Bool {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        return XCTWaiter().wait(for: [match], timeout: timeout) == .completed
    }
}
