import XCTest

/// The controls tutorial on the bundled Pepper&Carrot sample
/// (`ReaderTutorial`): replayed from Settings > Remote and Controller, and
/// offered once when a reader first opens (`-readerTutorialOffer`). XCUITest
/// can't tap the touch surface, so the runs stop at the page-number step.
final class ReaderTutorialUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private var step: XCUIElement { app.element("reader.tutorial.step") }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format); value=\(String(describing: element.exists ? element.value : nil))",
                       file: file, line: line)
    }

    private func openFromSettings(_ mode: String) {
        app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.controls"))
        if mode != "paged" {
            // The Vertical tab offers the vertical tutorial.
            select(app.element("controls.tab.\(mode)"), .right)
        }
        let button = app.element("controls.tutorial.\(mode)")
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Remote and Controller has no tutorial button")
        focus(button, .down)
        remote.press(.select)
        XCTAssertTrue(step.waitForExistence(timeout: 15), "the tutorial didn't start")
    }

    func testPagedTutorialFromSettingsAdvancesAndMenuLeavesIt() {
        openFromSettings("paged")
        XCTAssertTrue(app.element("reader.paged").exists)
        wait(step, "value == 'turnPage'")
        XCTAssertTrue(step.label.contains("Step 1 of"), step.label)
        // Other buttons don't break it.
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.5)
        wait(step, "value == 'turnPage'")
        // The sample reads left to right.
        remote.press(.right)
        wait(step, "value == 'showPageNumber'")
        XCTAssertEqual(app.staticTexts["reader.pageIndicator"].label, "2 / 3")
        // Menu with nothing open leaves the tutorial, back to Settings.
        remote.press(.menu)
        wait(step, "exists == false")
        XCTAssertTrue(app.element("controls.tutorial.paged").waitForExistence(timeout: 5))
    }

    func testVerticalTutorialStartsWithScrolling() {
        openFromSettings("webtoon")
        XCTAssertTrue(app.element("reader.webtoon").exists)
        wait(step, "value == 'scroll'")
        wait(app.element("reader.webtoon.strip"), "value BEGINSWITH 'focused'")
        remote.press(.down)
        wait(step, "value == 'showPageNumber'")
        remote.press(.menu)
        wait(step, "exists == false")
    }

    func testSettingsCreditsTheSample() {
        app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.controls"))
        XCTAssertTrue(app.element("controls.tutorial.paged").waitForExistence(timeout: 5))
        let credit = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'David Revoy'")).firstMatch
        XCTAssertTrue(credit.exists, "the CC BY credit is on the page")
        XCTAssertTrue(credit.label.contains("CC BY 4.0"))
    }

    // MARK: First-open offer

    private func launchDemoWithOffer() {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerTutorialOffer"]
        app.launch()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15), "the first reader open offers the tutorial")
        XCTAssertTrue(app.alerts.firstMatch.label.contains("Learn the Controls"), app.alerts.firstMatch.label)
    }

    func testFirstOpenOfferNotNowKeepsReading() {
        launchDemoWithOffer()
        select(app.alerts.buttons["Not Now"].firstMatch, .right)
        wait(app.alerts.firstMatch, "exists == false")
        XCTAssertFalse(step.exists)
        let indicator = app.staticTexts["reader.pageIndicator"]
        wait(indicator, "label == '1 / 6'")
        remote.press(.left)
        wait(indicator, "label == '2–3 / 6'")
    }

    func testFirstOpenOfferShowMeRunsTheTutorialThenReturns() {
        launchDemoWithOffer()
        select(app.alerts.buttons["Show Me"].firstMatch)
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        wait(step, "value == 'turnPage'")
        remote.press(.menu)
        wait(step, "exists == false")
        // Back on the chapter that was opened.
        wait(app.staticTexts["reader.pageIndicator"], "label == '1 / 6'")
        XCTAssertTrue(app.element("reader.paged").exists)
    }
}
