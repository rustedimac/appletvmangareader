import XCTest

/// The reader controls John chose (docs/READER_CONTROLS.md section 10,
/// `ReaderControls`): holding Play/Pause opens the reader options in every
/// reader, a press plays (auto-scroll, or the page-turn timer), Menu (Back)
/// closes one layer at a time even when the reader is in a full-screen
/// cover, a tap on the touch surface shows the page number with the
/// "Hold for options" hint, the options end with the Controls legend, the
/// first-use hint names the route, and Settings lists the whole button map.
final class ReaderControlsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchReader(_ mode: String, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerMode", mode] + extra
        app.launch()
        XCTAssertTrue(element(mode == "webtoon" ? "reader.webtoon" : "reader.paged").waitForExistence(timeout: 15),
                      "\(mode) reader didn't open")
        if mode == "webtoon" {
            wait(element("reader.webtoon.strip"), "value BEGINSWITH 'focused'", timeout: 15)
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

    // MARK: Options route

    func testVerticalHoldingPlayPauseOpensOptionsAndPressingPlays() {
        launchReader("webtoon")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(menu.exists, "a click no longer opens the options")
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "a Play/Pause press starts auto-scroll")
        XCTAssertFalse(menu.exists)
        remote.holdPlayPause()
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "holding Play/Pause opens the options")
        wait(badge, "exists == false")
        remote.press(.menu)
        wait(menu, "exists == false")
        XCTAssertTrue(element("reader.webtoon").exists, "Menu closes the options first, not the reader")

        // Auto-scroll still starts and stops with Play/Pause afterwards.
        wait(element("reader.webtoon.strip"), "value BEGINSWITH 'focused'")
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.playPause)
        wait(badge, "exists == false")
    }

    func testPagedHoldingPlayPauseOpensOptionsAndPressClosesThem() {
        launchReader("paged", ["-readerLayout", "single"])
        let indicator = app.staticTexts["reader.pageIndicator"]
        wait(indicator, "label == '1 / 6'")
        remote.holdPlayPause()
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "holding Play/Pause opens the options")
        XCTAssertEqual(element("reader.menu.autoScroll.value").label, "Slow", "the page timer's named speed")
        // A Play/Pause press closes the options.
        remote.press(.playPause)
        wait(menu, "exists == false")
        XCTAssertTrue(element("reader.paged").exists)
    }

    func testPagedPlayPauseStartsAndStopsThePageTimer() {
        launchReader("paged")
        let timer = element("reader.paged.pageTimer")
        XCTAssertFalse(timer.exists)
        remote.press(.playPause)
        XCTAssertTrue(timer.waitForExistence(timeout: 5), "a Play/Pause press starts the page timer")
        XCTAssertEqual(timer.label, "Page timer · Slow")
        XCTAssertFalse(menu.exists, "a press plays; only a hold opens the options")
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.playPause)
        wait(timer, "exists == false")
        // Menu (Back) stops it too, before it would close the reader.
        remote.press(.playPause)
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        remote.press(.menu)
        wait(timer, "exists == false")
        XCTAssertTrue(element("reader.paged").exists)
    }

    func testOptionsEndWithTheControlsLegend() {
        launchReader("paged")
        remote.holdPlayPause()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let legend = element("reader.menu.controls")
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "the Controls legend is in the options")
        let hold = element("controls.reader.remote.Hold Play/Pause")
        XCTAssertTrue(hold.exists)
        XCTAssertTrue(hold.label.contains("Reader options"), hold.label)
    }

    // MARK: Back

    func testBackClosesOneLayerAtATimeInAFullScreenCover() {
        launchReader("paged", ["-readerDemoCover"])
        remote.holdPlayPause()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        remote.press(.menu)
        wait(menu, "exists == false")
        XCTAssertTrue(element("reader.paged").exists, "the first Menu closes the options, not the reader")
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.menu)
        wait(element("reader.paged"), "exists == false")
        XCTAssertTrue(element("demo.openReader").waitForExistence(timeout: 5), "the second Menu closes the reader")
    }

    func testVerticalBackClosesTheOptionsInAFullScreenCover() {
        launchReader("webtoon", ["-readerDemoCover"])
        remote.holdPlayPause()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        remote.press(.menu)
        wait(menu, "exists == false")
        XCTAssertTrue(element("reader.webtoon").exists, "the first Menu closes the options, not the reader")
    }

    // MARK: Page number on tap

    /// XCUITest can't tap the touch surface without a click, so this checks
    /// only that the page number hides until one (`ReaderHUDPolicy`) and
    /// that a click doesn't show it. Tapping is checked on a real Apple TV.
    func testPageNumberHidesUntilATap() {
        launchReader("paged", ["-readerHUDOnTap"])
        XCTAssertFalse(app.staticTexts["reader.pageIndicator"].exists, "the page number hides until a tap")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(element("reader.hud.hint").exists, "a click is not a tap")
        XCTAssertFalse(app.staticTexts["reader.pageIndicator"].exists)
    }

    // MARK: First-use hint

    func testVerticalHintNamesTheRouteAndGoesAwayWithTheOptions() {
        launchReader("webtoon", ["-readerHints"])
        let hint = element("reader.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "first open shows the controls hint")
        XCTAssertTrue(hint.label.contains("Hold Play/Pause for reader options"), hint.label)
        XCTAssertTrue(hint.label.contains("Play/Pause auto-scrolls"), hint.label)
        remote.holdPlayPause()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        wait(hint, "exists == false")
        remote.press(.menu)
        wait(menu, "exists == false")
        XCTAssertFalse(hint.exists, "the hint doesn't come back once the options were opened")
    }

    func testPagedHintShowsOnFirstOpen() {
        launchReader("paged", ["-readerHints"])
        let hint = element("reader.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertTrue(hint.label.contains("Hold Play/Pause for reader options"), hint.label)
    }

    // MARK: Settings

    func testSettingsListsTheButtonMap() {
        app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.controls"))
        let hold = app.element("controls.paged.Hold Play/Pause")
        XCTAssertTrue(hold.waitForExistence(timeout: 5), "Remote and Controller page didn't open")
        XCTAssertTrue(hold.label.contains("Reader options"), hold.label)
        XCTAssertTrue(app.element("controls.paged.Play/Pause").label.contains("timer"))
        // A legend, not rows: the entries take no focus, only the tabs (and
        // the tutorial button) do.
        XCTAssertFalse(app.buttons["controls.paged.Hold Select"].exists, "legend entries must not be buttons")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'controls.paged.'")).count, 0)
        XCTAssertTrue(app.element("controls.tutorial.paged").exists)
        // Another tab swaps the legend in place, without scrolling.
        let gamepad = app.element("controls.tab.gamepad")
        select(gamepad, .right)
        XCTAssertTrue(app.element("controls.gamepad.B").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("controls.paged.Hold Select").exists)
        XCTAssertFalse(app.element("controls.tutorial.paged").exists)
    }
}
