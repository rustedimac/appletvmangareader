import XCTest

/// Menu (Back) with the reader options open closes the options, never the
/// reader (TESTING_GUIDE CTL-05), in every reader and whatever the options
/// are showing. The reader runs in a full-screen cover here (`-readerDemoCover`,
/// as the app presents it), where a Menu press that no view takes dismisses
/// the cover: focus that drops out of the drawer used to close the reader.
/// One test opens the reader from series detail on the demo servers, the
/// way people do.
final class ReaderBackUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launchReader(_ mode: String, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerDemoCover", "-readerMode", mode] + extra
        app.launch()
        XCTAssertTrue(reader(mode).waitForExistence(timeout: 15), "\(mode) reader didn't open")
        if mode == "webtoon" {
            wait(element("reader.webtoon.strip"), "value BEGINSWITH 'focused'", timeout: 15)
        } else {
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func reader(_ mode: String) -> XCUIElement { element(mode == "webtoon" ? "reader.webtoon" : "reader.paged") }
    private var drawer: XCUIElement { element("reader.menu") }
    private var menu: MenuRowDriver { MenuRowDriver(app: app, prefix: "reader.menu") }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format)", file: file, line: line)
    }

    private func openOptions(file: StaticString = #filePath, line: UInt = #line) {
        remote.holdPlayPause()
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "holding Play/Pause didn't open the options",
                      file: file, line: line)
        wait(element("reader.menu.mode"), "hasFocus == true", file: file, line: line)
    }

    /// Menu closes the options and the reader stays open.
    private func backClosesOptions(_ mode: String, file: StaticString = #filePath, line: UInt = #line) {
        remote.press(.menu)
        wait(drawer, "exists == false", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(reader(mode).exists, "Menu closed the reader, not just the options", file: file, line: line)
        XCTAssertFalse(element("demo.openReader").exists, "the reader's cover was dismissed", file: file, line: line)
    }

    // MARK: Options tabs and rows

    func testPagedBackFromSettingsTab() {
        launchReader("paged")
        openOptions()
        backClosesOptions("paged")
        // Back again now closes the reader.
        remote.press(.menu)
        XCTAssertTrue(element("demo.openReader").waitForExistence(timeout: 5))
    }

    func testPagedBackFromChaptersTab() {
        launchReader("paged")
        openOptions()
        menu.press("tab.chapters")
        wait(element("reader.menu.chapter.demo-1"), "hasFocus == true")
        backClosesOptions("paged")
    }

    func testPagedBackFromBookmarksTab() {
        launchReader("paged")
        openOptions()
        menu.press("tab.bookmarks")
        XCTAssertTrue(element("reader.menu.bookmarks.empty").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        backClosesOptions("paged")
    }

    func testPagedBackClosesChoicesThenOptions() {
        launchReader("paged")
        openOptions()
        menu.press("direction")
        wait(element("reader.menu.direction.rightToLeft"), "hasFocus == true")
        remote.press(.menu)
        wait(element("reader.menu.direction"), "hasFocus == true")
        XCTAssertTrue(drawer.exists, "the first Menu closes only the choices")
        backClosesOptions("paged")
    }

    func testPagedBackAfterSetAsDefaultAndReset() {
        launchReader("paged")
        openOptions()
        menu.pick("layout.single")
        menu.press("makeDefault")
        wait(element("reader.menu.isDefault"), "exists == true")
        Thread.sleep(forTimeInterval: 0.5)
        backClosesOptions("paged")
        openOptions()
        menu.pick("layout.double")
        menu.press("resetToDefault")
        wait(element("reader.menu.isDefault"), "exists == true")
        Thread.sleep(forTimeInterval: 0.5)
        backClosesOptions("paged")
    }

    func testPagedBackFromTheControlsLegend() {
        launchReader("paged")
        openOptions()
        // Scroll to the bottom of the options, past the last focusable row.
        for _ in 0..<30 { remote.press(.down) }
        XCTAssertTrue(element("reader.menu.controls").exists)
        Thread.sleep(forTimeInterval: 0.5)
        backClosesOptions("paged")
    }

    func testBackAfterSwitchingPagedToVertical() {
        launchReader("paged")
        openOptions()
        menu.pick("mode.webtoon")
        XCTAssertTrue(reader("webtoon").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        backClosesOptions("webtoon")
    }

    // MARK: Other readers and states

    func testZoomedPagedBackClosesOptionsThenZoomsOut() {
        launchReader("paged")
        remote.press(.select, forDuration: 1.0)
        XCTAssertTrue(element("reader.zoom").waitForExistence(timeout: 5), "holding Select didn't zoom")
        openOptions()
        backClosesOptions("paged")
        XCTAssertTrue(element("reader.zoom").exists, "closing the options keeps the zoom")
        remote.press(.menu)
        wait(element("reader.zoom"), "exists == false")
        XCTAssertTrue(reader("paged").exists, "the second Menu zooms out, not closes")
    }

    func testPagedBackWhileThePageTimerRan() {
        launchReader("paged")
        remote.press(.playPause)
        XCTAssertTrue(element("reader.paged.pageTimer").waitForExistence(timeout: 5))
        openOptions()
        backClosesOptions("paged")
    }

    func testVerticalBackFromChaptersTab() {
        launchReader("webtoon")
        openOptions()
        menu.press("tab.chapters")
        wait(element("reader.menu.chapter.demo-1"), "hasFocus == true")
        backClosesOptions("webtoon")
    }

    func testVerticalBackWhileAutoScrolling() {
        launchReader("webtoon")
        remote.press(.playPause)
        XCTAssertTrue(element("reader.webtoon.autoScroll").waitForExistence(timeout: 5))
        openOptions()
        backClosesOptions("webtoon")
    }

    func testPagedBackFromThePageScrubberOpenedInOptions() {
        launchReader("paged")
        openOptions()
        menu.press("browsePages")
        XCTAssertTrue(element("reader.scrubber").waitForExistence(timeout: 5))
        remote.press(.menu)
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "Menu goes back from the scrubber to the options")
        wait(element("reader.scrubber"), "exists == false")
        backClosesOptions("paged")
    }

    // MARK: From series detail

    func testBackClosesOptionsInAReaderOpenedFromSeriesDetail() {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"]
        app.launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
        for _ in 0..<6 where !poster.exists {
            remote.press(.down)
            usleep(350_000)
        }
        XCTAssertTrue(poster.exists, "no poster took focus")
        remote.press(.select)
        let start = app.buttons["series.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        for _ in 0..<3 where !start.hasFocus {
            remote.press(.left)
            usleep(350_000)
        }
        XCTAssertTrue(start.hasFocus, "Start should be focusable")
        remote.press(.select)
        XCTAssertTrue(reader("paged").waitForExistence(timeout: 15), "reader didn't open")
        Thread.sleep(forTimeInterval: 1)
        openOptions()
        remote.press(.menu)
        wait(drawer, "exists == false")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(reader("paged").exists, "Menu closed the reader, not just the options")
        remote.press(.menu)
        wait(reader("paged"), "exists == false")
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the second Menu goes back to the series")
    }
}
