import XCTest

/// Drives the in-reader menu on the demo series (`-readerDemo`). Chapter 1
/// has 6 pages with page 4 wide, so in two-page layout it reads
/// 1 | 2–3 | 4 | 5–6. Chapter 3 has 4 pages.
final class ReaderMenuUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"] + extra
        app.launch()
        XCTAssertTrue(element("reader.paged").waitForExistence(timeout: 15))
        expectIndicator("1 / 6")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func menuItem(_ id: String) -> XCUIElement { element("reader.menu.\(id)") }
    private var indicator: XCUIElement { app.staticTexts["reader.pageIndicator"] }

    private func expectIndicator(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: indicator)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed,
                       "Expected page indicator \"\(text)\", got \"\(indicator.exists ? indicator.label : "<missing>")\"",
                       file: file, line: line)
    }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format)", file: file, line: line)
    }

    private func openMenu() {
        remote.press(.down)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        wait(menuItem("mode.paged"), "hasFocus == true")
    }

    private func closeMenu() {
        remote.press(.menu)
        wait(element("reader.menu"), "exists == false")
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Moves focus to a menu control with the remote, the way a person would:
    /// up/down to reach its row, then left/right along the row.
    private func moveFocus(to id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = menuItem(id)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "No \(id)", file: file, line: line)
        for _ in 0..<25 {
            if target.hasFocus { return }
            let current = focused
            guard current.exists else { Thread.sleep(forTimeInterval: 0.3); continue }
            let a = current.frame
            let b = target.frame
            if b.midY > a.maxY {
                remote.press(.down)
            } else if b.midY < a.minY {
                remote.press(.up)
            } else if b.midX > a.midX {
                remote.press(.right)
            } else {
                remote.press(.left)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(target.hasFocus, "Couldn't move focus to \(id)", file: file, line: line)
    }

    private func choose(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        moveFocus(to: id, file: file, line: line)
        remote.press(.select)
    }

    // MARK: Tests

    func testOpensOnCurrentModeWithPagedRows() {
        launch()
        openMenu()
        XCTAssertTrue(menuItem("mode.paged").isSelected)
        XCTAssertFalse(menuItem("mode.webtoon").isSelected)
        XCTAssertTrue(menuItem("layout.double").isSelected)
        XCTAssertTrue(menuItem("direction.rightToLeft").isSelected)
        XCTAssertTrue(menuItem("firstPageAlone.on").isSelected)
        XCTAssertTrue(menuItem("firstPageAlone.hint").exists)
        XCTAssertFalse(menuItem("shiftPairing").exists)   // folded into First Page Alone
        XCTAssertTrue(menuItem("background.black").isSelected)
        XCTAssertFalse(menuItem("webtoonWidth.value").exists)
        XCTAssertEqual(menuItem("position").label, "Page 1 of 6")
    }

    func testSingleLayoutAppliesLiveAndHidesPairing() {
        launch()
        openMenu()
        choose("layout.single")
        wait(menuItem("layout.single"), "isSelected == true")
        wait(menuItem("firstPageAlone.on"), "exists == false")
        closeMenu()
        remote.press(.left)
        expectIndicator("2 / 6")
        remote.press(.left)
        expectIndicator("3 / 6")
    }

    /// First Page Alone is the one pairing fix: Off re-pairs the spreads
    /// (what "Shift by one" used to do), On puts them back.
    func testFirstPageAloneRepairsPairsBothWays() {
        launch()
        openMenu()
        choose("firstPageAlone.off")
        wait(menuItem("firstPageAlone.off"), "isSelected == true")
        // The cover now pairs with page 2 behind the menu.
        wait(menuItem("position"), "label == 'Pages 1–2 of 6'")
        closeMenu()
        expectIndicator("1–2 / 6")
        remote.press(.left)
        expectIndicator("3 / 6")       // page 3 can't pair with the wide page 4
        openMenu()
        choose("firstPageAlone.on")
        wait(menuItem("firstPageAlone.on"), "isSelected == true")
        closeMenu()
        expectIndicator("2–3 / 6")
    }

    func testDirectionLeftToRight() {
        launch()
        openMenu()
        choose("direction.leftToRight")
        wait(menuItem("direction.leftToRight"), "isSelected == true")
        closeMenu()
        remote.press(.right)
        expectIndicator("2–3 / 6")
        remote.press(.left)
        expectIndicator("1 / 6")
    }

    func testVerticalModeSwapsRowsAndStepsWidth() {
        launch()
        openMenu()
        choose("mode.webtoon")
        wait(menuItem("mode.webtoon"), "isSelected == true")
        XCTAssertTrue(element("reader.webtoon").waitForExistence(timeout: 5))
        wait(menuItem("layout.double"), "exists == false")
        XCTAssertFalse(menuItem("firstPageAlone.on").exists)
        XCTAssertEqual(menuItem("webtoonWidth.value").label, "60%")
        choose("webtoonWidth.increase")
        wait(menuItem("webtoonWidth.value"), "label == '70%'")
        remote.press(.select)
        wait(menuItem("webtoonWidth.value"), "label == '80%'")
        choose("webtoonWidth.decrease")
        wait(menuItem("webtoonWidth.value"), "label == '70%'")
        // Back to paged: the paged rows come back with their old values.
        choose("mode.paged")
        wait(menuItem("layout.double"), "isSelected == true")
        closeMenu()
        XCTAssertTrue(element("reader.paged").waitForExistence(timeout: 5))
        remote.press(.left)
        expectIndicator("2–3 / 6")
    }

    func testBackgroundChoice() {
        launch()
        openMenu()
        choose("background.white")
        wait(menuItem("background.white"), "isSelected == true")
        XCTAssertFalse(menuItem("background.black").isSelected)
    }

    func testChapterListJumpsToChapter() {
        launch()
        openMenu()
        choose("tab.chapters")
        // The open chapter is marked and focused.
        wait(menuItem("chapter.demo-1"), "hasFocus == true")
        XCTAssertTrue(menuItem("chapter.demo-1").isSelected)
        choose("chapter.demo-3")
        wait(element("reader.menu"), "exists == false")
        expectIndicator("1 / 4")
    }

    func testChapterListReturnsToTheExactPageLeft() {
        launch()
        remote.press(.left)
        remote.press(.left)
        expectIndicator("4 / 6")
        openMenu()
        choose("tab.chapters")
        choose("chapter.demo-3")
        expectIndicator("1 / 4")
        openMenu()
        choose("tab.chapters")
        choose("chapter.demo-1")
        wait(element("reader.menu"), "exists == false")
        expectIndicator("4 / 6")
    }

    func testSetAsDefaultAndReset() {
        launch()
        openMenu()
        XCTAssertTrue(menuItem("isDefault").exists)       // demo starts on the default
        choose("layout.single")
        wait(menuItem("isDefault"), "exists == false")
        choose("makeDefault")
        wait(menuItem("isDefault"), "exists == true")
        choose("layout.double")
        wait(menuItem("isDefault"), "exists == false")
        choose("resetToDefault")
        wait(menuItem("layout.single"), "isSelected == true")
        XCTAssertTrue(menuItem("isDefault").exists)
    }

    func testPlayPauseClosesMenuAndPagesStillTurn() {
        launch()
        openMenu()
        remote.press(.playPause)
        wait(element("reader.menu"), "exists == false")
        remote.press(.left)
        expectIndicator("2–3 / 6")
    }

    /// The title and tabs scroll with the options. They used to stay pinned
    /// while the rows slid underneath, so both were drawn over each other.
    func testHeaderScrollsWithOptions() {
        launch()
        openMenu()
        let title = menuItem("title")
        let tab = menuItem("tab.settings")
        let firstRow = menuItem("mode.paged")
        XCTAssertTrue(title.frame.maxY <= tab.frame.minY + 1, "title should start above the tabs")

        moveFocus(to: "resetToDefault")
        Thread.sleep(forTimeInterval: 0.6)
        // Wherever the scroll ends up, the rows stay below the tabs.
        XCTAssertGreaterThanOrEqual(firstRow.frame.minY, tab.frame.maxY - 1, "options are drawn under the tabs")
        if title.exists, title.frame.maxY > 0 {
            XCTAssertLessThanOrEqual(title.frame.maxY, tab.frame.minY + 1, "title is drawn over the tabs")
        }

        // Back up to the tabs: the title comes back into view above them.
        moveFocus(to: "tab.settings")
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertGreaterThanOrEqual(title.frame.minY, 0, "title didn't scroll back into view")
        XCTAssertTrue(title.frame.maxY <= tab.frame.minY + 1)
    }

    /// Settings / Chapters / Bookmarks are tabs, drawn like the top tab bar:
    /// text only, one line ("Bookmarks" used to wrap), the open one marked
    /// with the selected trait. Passing over a tab doesn't open it; a click does.
    func testSectionTabsLookLikeTheTopBar() {
        launch()
        openMenu()
        let ids = ["tab.settings", "tab.chapters", "tab.bookmarks"]
        assertSectionTabLayout(app, track: "reader.menu.tabs", tabs: ids.map { "reader.menu.\($0)" },
                               titles: ["Settings", "Chapters", "Bookmarks"])
        XCTAssertTrue(menuItem("tab.settings").isSelected)
        XCTAssertFalse(menuItem("tab.chapters").isSelected)

        // Focus over the tabs (Settings → Bookmarks passes Chapters): still on Settings.
        moveFocus(to: "tab.settings")
        moveFocus(to: "tab.bookmarks")
        XCTAssertTrue(menuItem("tab.settings").isSelected)
        XCTAssertTrue(menuItem("mode.paged").exists, "moving focus switched the pane")
        // With focus on a tab it still fits on one line (focus grows it).
        assertSectionTabLayout(app, track: "reader.menu.tabs", tabs: ids.map { "reader.menu.\($0)" },
                               titles: ["Settings", "Chapters", "Bookmarks"])

        remote.press(.select)
        wait(menuItem("tab.bookmarks"), "isSelected == true")
        XCTAssertFalse(menuItem("tab.settings").isSelected)
        XCTAssertFalse(menuItem("mode.paged").exists)
    }
}
