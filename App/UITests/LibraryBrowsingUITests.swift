import XCTest

/// Big-library browsing against the offline demo servers: sort options,
/// the A–Z jump bar, right-to-left grids, poster size, a library's reading
/// direction, and the customizable Home (hide/reorder rows, remove from
/// Continue Reading, Caught Up). Demo titles cycle through eight words, so
/// in title order the grid holds every "Ember" series, then "Harbor", and
/// so on (see `SampleLibraryServer`).
final class LibraryBrowsingUITests: XCTestCase {
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

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format). Focus: \(focusedDescription())", file: file, line: line)
    }

    /// Moves focus toward `element` by comparing frames, like a person
    /// would with the remote.
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
            // A List row that isn't on screen yet reports an empty frame;
            // keep scrolling down to it.
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

    /// Library tab → Demo Kavita → its grid.
    private func openKavitaLibrary() {
        selectTab("Library")
        let server = app.buttons["library.server.Demo Kavita"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        moveFocus(to: server)
        remote.press(.select)
        XCTAssertTrue(app.buttons["category.all"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["poster.1"].waitForExistence(timeout: 10))
    }

    /// Opens "Sort & View" for the selected category and picks an option.
    private func pickOption(_ id: String) {
        let options = app.buttons["library.options"]
        moveFocus(to: options)
        remote.press(.select)
        let choice = app.buttons[id]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        moveFocus(to: choice)
        remote.press(.select)
        wait(choice, "value == 'selected'")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["category.all"].waitForExistence(timeout: 10))
    }

    /// From the grid, presses right until a letter of the jump bar has
    /// focus, then moves to `letter` and clicks it.
    private func jump(to letter: String) {
        let anyLetter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.jump.' AND hasFocus == true")).firstMatch
        for _ in 0..<10 where !anyLetter.exists {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(anyLetter.exists, "jump bar never took focus. Focus: \(focusedDescription())")
        let target = app.buttons["library.jump.\(letter)"]
        for _ in 0..<30 where !target.hasFocus {
            remote.press(target.frame.midY > focused.frame.midY ? .down : .up)
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(target.hasFocus, "couldn't focus letter \(letter)")
        remote.press(.select)
    }

    private func focusGrid() {
        moveFocus(to: app.buttons["poster.1"])
    }

    /// Presses down until `element` exists (rows further down a lazy
    /// stack only exist once scrolled near).
    private func scrollDown(until element: XCUIElement, maxPresses: Int = 15) {
        for _ in 0..<maxPresses where !element.exists {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(element.exists, "\(element) never appeared. Focus: \(focusedDescription())")
    }

    private var focusedPoster: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    }

    /// Presses `direction` until focus stops moving (the end of a row).
    private func pressUntilFocusStops(_ direction: XCUIRemote.Button, maxPresses: Int = 60) {
        var last = ""
        for _ in 0..<maxPresses {
            remote.press(direction)
            Thread.sleep(forTimeInterval: 0.4)
            let current = focused
            let now = "\(current.identifier)|\(current.frame)"
            if now == last { return }
            last = now
        }
    }

    /// Settings → Customize Home.
    private func openCustomizeHome() {
        selectTab("Settings")
        // Still open from last time: the Settings tab keeps its place.
        if app.buttons["homeLayout.toggle.continueReading"].waitForExistence(timeout: 2) { return }
        let link = app.buttons["settings.customizeHome"]
        moveFocus(to: link)
        remote.press(.select)
        XCTAssertTrue(app.buttons["homeLayout.toggle.continueReading"].waitForExistence(timeout: 10))
    }

    // MARK: Library

    func testJumpBarLoadsLaterPagesAndFocusesTheLetter() {
        launch()
        openKavitaLibrary()
        focusGrid()
        // "Willow" starts at item 68, on the second page of 48.
        jump(to: "W")
        let willow = app.buttons["poster.7"]
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.'"))
        XCTAssertTrue(willow.waitForExistence(timeout: 15),
                      "Willow Chronicles 7 never loaded. Posters: \(posters.allElementsBoundByIndex.map(\.identifier)). Focus: \(focusedDescription())")
        wait(willow, "hasFocus == true", timeout: 15)

        // Back to the top with "#" (no titles start with a digit, so the first).
        jump(to: "#")
        wait(app.buttons["poster.1"], "hasFocus == true", timeout: 15)
    }

    func testSortByTitleDescendingAndRecentlyAdded() {
        launch()
        openKavitaLibrary()
        pickOption("libraryOptions.sort.titleDescending")
        // Z–A: "Zephyr Chronicles 88" comes first.
        let first = app.buttons["poster.88"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["library.jump.A"].exists, "title sorts keep the jump bar")
        moveFocus(to: first)
        jump(to: "M")
        wait(app.buttons["poster.84"], "hasFocus == true", timeout: 15)

        pickOption("libraryOptions.sort.recentlyAdded")
        XCTAssertTrue(app.buttons["poster.90"].waitForExistence(timeout: 10), "newest first")
        XCTAssertFalse(app.buttons["library.jump.A"].exists, "no A–Z bar unless sorted by title")
    }

    func testRightToLeftGridAndSmallerPosters() {
        launch()
        openKavitaLibrary()
        let first = app.buttons["poster.1"], second = app.buttons["poster.9"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertLessThan(first.frame.minX, second.frame.minX, "left to right by default")
        let standardWidth = first.frame.width

        pickOption("libraryOptions.gridOrder.rightToLeft")
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(first.frame.minX, second.frame.minX, "first series at the top right")

        pickOption("libraryOptions.density.compact")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertLessThan(first.frame.width, standardWidth * 0.9, "small posters")
    }

    // MARK: Poster caption (one test per mode)

    /// Demo series 1 has 4 chapters of 20 pages, none read.
    private var caption: XCUIElement { app.staticTexts["poster.caption.1"] }
    private var titleProgress: XCUIElement { app.descendants(matching: .any)["poster.titleProgress.1"] }

    func testPosterCaptionShowsChaptersByDefault() {
        launch()
        openKavitaLibrary()
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        XCTAssertEqual(caption.label, "4 chapters")
        XCTAssertFalse(titleProgress.exists)
    }

    func testPosterCaptionPages() {
        launch()
        openKavitaLibrary()
        pickOption("libraryOptions.caption.pages")
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        wait(caption, "label == '80 pages'")
    }

    func testPosterCaptionProgressBar() {
        launch()
        openKavitaLibrary()
        pickOption("libraryOptions.caption.progress")
        XCTAssertTrue(titleProgress.waitForExistence(timeout: 10), "progress bar under the title")
        XCTAssertEqual(titleProgress.value as? String, "0 percent")
        XCTAssertFalse(caption.exists, "no count text with the progress bar")
    }

    func testPosterCaptionOff() {
        launch()
        openKavitaLibrary()
        pickOption("libraryOptions.caption.off")
        XCTAssertTrue(app.buttons["poster.1"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(caption.exists)
        XCTAssertFalse(titleProgress.exists)
        // The setting is the profile's, so Home follows it too.
        selectTab("Home")
        XCTAssertTrue(app.staticTexts["shelf.Demo Kavita.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.caption.'")).count, 0)
    }

    func testLibraryReadingDirectionOpensSeriesThatWay() {
        launch()
        openKavitaLibrary()
        // The profile default is right to left; this library reads left to right.
        pickOption("libraryOptions.style.leftToRight")
        let poster = app.buttons["poster.1"]
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        moveFocus(to: poster)
        remote.press(.select)
        let start = app.buttons["series.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        moveFocus(to: start)
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["reader.paged"].waitForExistence(timeout: 15))
        remote.press(.down)
        let ltr = app.descendants(matching: .any)["reader.menu.direction.leftToRight"]
        XCTAssertTrue(ltr.waitForExistence(timeout: 10), "reader menu didn't open")
        XCTAssertTrue(ltr.isSelected, "series opened with the library's direction")
    }

    // MARK: Home

    func testHideAndReorderHomeRows() {
        launch()
        let updated = app.staticTexts["shelf.recentlyUpdated"]
        let added = app.staticTexts["shelf.newlyAdded"]
        XCTAssertTrue(updated.waitForExistence(timeout: 15), "Recently Updated is the first row with content")

        openCustomizeHome()
        let up = app.buttons["homeLayout.up.newlyAdded"]
        moveFocus(to: up)
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.5)
        moveFocus(to: up)
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.5)

        selectTab("Home")
        XCTAssertTrue(added.waitForExistence(timeout: 10), "Newly Added moved to the top")
        if updated.exists {
            XCTAssertLessThan(added.frame.minY, updated.frame.minY, "Newly Added above Recently Updated")
        }

        openCustomizeHome()
        let toggle = app.buttons["homeLayout.toggle.newlyAdded"]
        moveFocus(to: toggle)
        remote.press(.select)
        wait(toggle, "value == 'hidden'")

        selectTab("Home")
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
        XCTAssertFalse(added.exists, "hidden row is gone")
    }

    func testRemoveFromContinueReading() {
        launch()
        // Read something so Continue Reading has a row.
        openKavitaLibrary()
        let poster = app.buttons["poster.1"]
        moveFocus(to: poster)
        remote.press(.select)
        let start = app.buttons["series.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        moveFocus(to: start)
        remote.press(.select)
        let reader = app.descendants(matching: .any)["reader.paged"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        remote.press(.menu)
        wait(reader, "exists == false")
        remote.press(.menu)

        selectTab("Home")
        let row = app.staticTexts["shelf.continueReading"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Continue Reading never showed")
        // Continue Reading is the first row, so the first poster down from
        // the tab bar is the series just read.
        let focusedPoster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
        for _ in 0..<4 where !focusedPoster.exists {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertEqual(focusedPoster.identifier, "poster.1")
        remote.press(.select, forDuration: 1.5)
        // The menu item may come through as a button, a cell or a menu item.
        let remove = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'poster.menu.removeFromContinueReading' OR label == 'Remove from Continue Reading'")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5),
                      "no long-press menu. Focus: \(focusedDescription()). Tree: \(app.debugDescription.prefix(3000))")
        // It's the only item, so it has focus.
        remote.press(.select)
        wait(row, "exists == false")
    }

    func testCaughtUpShowsFinishedSeries() {
        launch(["-demoFinished", "1"])
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        // Opening the finished series notices it's caught up.
        openKavitaLibrary()
        let poster = app.buttons["poster.1"]
        moveFocus(to: poster)
        remote.press(.select)
        let again = app.buttons["series.continue"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(again.label, "Read Again")
        remote.press(.menu)

        selectTab("Home")
        // Caught Up is the last row by default.
        scrollDown(until: app.staticTexts["shelf.caughtUp"])
    }

    func testDownFromAnyPosterInLastRowReachesCustomizeHome() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.Demo Kavita.recentlyUpdated"].waitForExistence(timeout: 15))
        let customize = app.buttons["home.customize"]
        scrollDown(until: customize, maxPresses: 20)
        moveFocus(to: customize)

        // Up lands in the last row. Its first poster sits far left of the
        // centered button, its last one far right: Down must work from both.
        for edge in [XCUIRemote.Button.left, .right] {
            remote.press(.up)
            wait(focusedPoster, "exists == true")
            pressUntilFocusStops(edge)
            let poster = focusedPoster
            XCTAssertTrue(poster.exists, "focus left the row. Focus: \(focusedDescription())")
            let frame = poster.frame
            XCTAssertTrue(frame.maxX < customize.frame.minX || frame.minX > customize.frame.maxX,
                          "\(edge == .left ? "first" : "last") poster \(frame) should not sit above the button \(customize.frame)")
            remote.press(.down)
            wait(customize, "hasFocus == true")
        }
    }

    // MARK: Search

    func testSearchShowsDictationHint() {
        launch()
        selectTab("Search")
        XCTAssertTrue(app.staticTexts["Search your servers"].waitForExistence(timeout: 10))
    }
}
