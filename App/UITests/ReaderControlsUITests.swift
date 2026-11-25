import XCTest

/// The route to the reader options in every reader (`ReaderControls`):
/// a click or holding Select opens them in the paged and vertical readers,
/// Play/Pause still runs auto-scroll in the vertical reader, the first-use
/// hint says so, and Settings lists the whole button map.
final class ReaderControlsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchReader(_ mode: String, hints: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerMode", mode] + (hints ? ["-readerHints"] : [])
        app.launch()
        XCTAssertTrue(element(mode == "webtoon" ? "reader.webtoon" : "reader.paged").waitForExistence(timeout: 15),
                      "\(mode) reader didn't open")
        if mode == "webtoon" {
            XCTAssertTrue(app.staticTexts["reader.webtoon.indicator"].waitForExistence(timeout: 15))
            wait(element("reader.webtoon.strip"), "value BEGINSWITH 'focused'")
        } else {
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private var menu: XCUIElement { element("reader.menu") }
    private var badge: XCUIElement { element("reader.webtoon.autoScroll") }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format)", file: file, line: line)
    }

    // MARK: Vertical reader

    func testVerticalClickOpensOptionsAndMenuButtonClosesThem() {
        launchReader("webtoon")
        remote.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "a click opens the reader options")
        remote.press(.menu)
        wait(menu, "exists == false")
        XCTAssertTrue(element("reader.webtoon").exists, "Menu closes the options first, not the reader")
    }

    func testVerticalHoldingSelectOpensOptionsEvenWhileAutoScrolling() {
        launchReader("webtoon")
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "Play/Pause still starts auto-scroll")
        XCTAssertFalse(menu.exists)
        remote.press(.select, forDuration: 1.2)
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "holding Select opens the options")
        wait(badge, "exists == false")
        remote.press(.menu)
        wait(menu, "exists == false")

        // Auto-scroll still starts and stops with Play/Pause afterwards.
        wait(element("reader.webtoon.strip"), "value BEGINSWITH 'focused'")
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.playPause)
        wait(badge, "exists == false")
    }

    func testVerticalHintNamesTheRouteAndGoesAwayWithTheOptions() {
        launchReader("webtoon", hints: true)
        let hint = element("reader.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "first open shows the controls hint")
        XCTAssertTrue(hint.label.contains("Click for reader options"), hint.label)
        XCTAssertTrue(hint.label.contains("Play/Pause auto-scrolls"), hint.label)
        remote.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        wait(hint, "exists == false")
        remote.press(.menu)
        wait(menu, "exists == false")
        XCTAssertFalse(hint.exists, "the hint doesn't come back once the options were opened")
    }

    // MARK: Paged reader

    func testPagedClickAndPlayPauseBothOpenOptions() {
        launchReader("paged")
        remote.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "a click opens the options, as in the vertical reader")
        remote.press(.menu)
        wait(menu, "exists == false")
        XCTAssertTrue(element("reader.paged").exists)
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.playPause)
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Play/Pause still opens them in the page reader")
    }

    func testPagedHintShowsOnFirstOpen() {
        launchReader("paged", hints: true)
        let hint = element("reader.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertTrue(hint.label.contains("Play/Pause for reader options"), hint.label)
    }

    // MARK: Settings

    func testSettingsListsTheButtonMap() {
        app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.controls"))
        let click = app.element("controls.paged.Click or hold Select")
        XCTAssertTrue(click.waitForExistence(timeout: 5), "Remote and Controller page didn't open")
        XCTAssertTrue(click.label.contains("Reader options"), click.label)
        XCTAssertTrue(app.element("controls.paged.Play/Pause").label.contains("Reader options"))
    }
}
