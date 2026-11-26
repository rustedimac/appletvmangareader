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

    /// Status and read-progress filters narrow the grid, the Sort & View
    /// button shows how many are on, an empty result offers Show
    /// Everything, and Library Defaults applies to libraries without their
    /// own filters. Demo statuses: every fifth series is on hiatus (unless
    /// a multiple of 7), see `SampleLibraryServer.status(for:)`.
    func testStatusFilterAndLibraryDefaults() {
        launch()
        openKavitaLibrary()
        pickOption("libraryFilter.status.hiatus")
        let options = app.buttons["library.options"]
        wait(options, "value == '1 filter'")
        XCTAssertTrue(app.buttons["poster.5"].waitForExistence(timeout: 10), "on hiatus")
        XCTAssertFalse(app.buttons["poster.1"].exists, "completed series are filtered out")
        XCTAssertFalse(app.buttons["poster.2"].exists, "ongoing series are filtered out")

        // Hiatus series 5 is unread, so "Finished" leaves nothing.
        pickOption("libraryFilter.read.read")
        wait(options, "value == '2 filters'")
        let clear = app.buttons["library.clearFilters"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        moveFocus(to: clear)
        remote.press(.select)
        XCTAssertTrue(app.buttons["poster.1"].waitForExistence(timeout: 10), "Show Everything clears this library's filters")
        wait(options, "value == ''")

        // Back to the default, then set the default to Ongoing in Library Defaults.
        pickOption("libraryOptions.filter.default")
        moveFocus(to: options)
        remote.press(.select)
        let defaultsLink = app.buttons["libraryOptions.defaults"]
        XCTAssertTrue(defaultsLink.waitForExistence(timeout: 10))
        moveFocus(to: defaultsLink)
        remote.press(.select)
        let ongoing = app.buttons["libraryFilter.status.ongoing"]
        XCTAssertTrue(ongoing.waitForExistence(timeout: 10))
        moveFocus(to: ongoing)
        remote.press(.select)
        wait(ongoing, "value == 'selected'")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["libraryOptions.filter.default"].waitForExistence(timeout: 10))
        remote.press(.menu)
        XCTAssertTrue(app.buttons["poster.2"].waitForExistence(timeout: 10), "the default filter shows ongoing series")
        XCTAssertFalse(app.buttons["poster.1"].exists)
        wait(options, "value == '1 filter'")
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
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.caption.'")).count, 0)
    }

    // MARK: Progress percentage

    private var titlePercent: XCUIElement { app.staticTexts["poster.titlePercent.1"] }

    /// Flips "Show Percentage Read" in Sort & View.
    private func toggleShowsPercent() {
        let options = app.buttons["library.options"]
        moveFocus(to: options)
        remote.press(.select)
        let toggle = app.descendants(matching: .any)["libraryOptions.showsPercent"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        moveFocus(to: toggle)
        let before = "\(toggle.value ?? "")"
        remote.press(.select)
        wait(toggle, "value != '\(before)'")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["category.all"].waitForExistence(timeout: 10))
    }

    func testPercentageNextToProgressBar() {
        launch()
        openKavitaLibrary()
        pickOption("libraryOptions.caption.progress")
        XCTAssertTrue(titlePercent.waitForExistence(timeout: 10), "percentage next to the bar (on by default)")
        XCTAssertEqual(titlePercent.label, "0%")
        // Same row as the bar, to its right, inside the poster's width.
        let poster = app.buttons["poster.1"]
        XCTAssertGreaterThan(titlePercent.frame.minX, titleProgress.frame.maxX - 1, "number sits right of the bar")
        XCTAssertLessThanOrEqual(titlePercent.frame.maxX, poster.frame.maxX + 1, "number doesn't run past the poster")
        XCTAssertGreaterThan(titleProgress.frame.width, 60, "bar keeps most of the width")
        XCTAssertLessThan(abs(titlePercent.frame.midY - titleProgress.frame.midY), 20, "number and bar share a row")
        toggleShowsPercent()
        XCTAssertTrue(titleProgress.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(titlePercent.exists, "setting off hides the number, keeps the bar")
    }

    /// Every poster in a row is the same height, so progress bars and
    /// their percentages line up across the row whatever the title's
    /// length (John, 2026-11-26).
    func testProgressBarsLineUpAcrossARow() {
        launch(["-demoProgress"])
        openKavitaLibrary()
        pickOption("libraryOptions.density.large")
        pickOption("libraryOptions.caption.progress")
        XCTAssertTrue(titlePercent.waitForExistence(timeout: 10))
        let firstCover = app.buttons["poster.1"].frame
        func row(_ query: XCUIElementQuery, _ prefix: String) -> [XCUIElement] {
            query.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
                .filter { $0.frame.width > 0 && $0.frame.minY > firstCover.maxY
                          && $0.frame.minY < firstCover.maxY + firstCover.height / 2 }
        }
        // Leave out the focused poster: its caption drops on purpose.
        let focusedX = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true"))
            .firstMatch.frame.midX
        func resting(_ items: [XCUIElement]) -> [XCUIElement] {
            items.filter { abs($0.frame.midX - focusedX) > firstCover.width / 2 }
        }
        let titles = resting(row(app.staticTexts, "poster.title."))
        let bars = resting(row(app.descendants(matching: .any), "poster.titleProgress."))
        let percents = resting(row(app.staticTexts, "poster.titlePercent."))
        XCTAssertGreaterThanOrEqual(bars.count, 3, "not enough posters in the first row")
        let heights = titles.map(\.frame.height)
        XCTAssertLessThan((heights.max() ?? 0) - (heights.min() ?? 0), 1, "titles take different heights: \(heights)")
        for (name, items) in [("bars", bars), ("percentages", percents)] {
            let tops = items.map(\.frame.minY)
            XCTAssertLessThan((tops.max() ?? 0) - (tops.min() ?? 0), 1, "\(name) don't line up: \(tops)")
        }
    }

    func testPercentageFitsOnSmallPosters() {
        launch()
        openKavitaLibrary()
        pickOption("libraryOptions.density.compact")
        pickOption("libraryOptions.caption.progress")
        XCTAssertTrue(titlePercent.waitForExistence(timeout: 10))
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.'")).allElementsBoundByIndex
        for id in ["1", "2", "3"] {
            let percent = app.staticTexts["poster.titlePercent.\(id)"]
            let bar = app.descendants(matching: .any)["poster.titleProgress.\(id)"]
            let poster = app.buttons["poster.\(id)"]
            guard percent.exists, poster.exists else { continue }
            XCTAssertEqual(percent.label, "0%")
            XCTAssertLessThanOrEqual(percent.frame.maxX, poster.frame.maxX + 1, "poster \(id): number clipped")
            XCTAssertGreaterThan(bar.frame.width, 30, "poster \(id): bar squeezed away")
            // The next poster in the row starts after this one's number.
            if let next = posters.first(where: { $0.identifier != poster.identifier
                && abs($0.frame.minY - poster.frame.minY) < 5 && $0.frame.minX > poster.frame.minX }) {
                XCTAssertLessThan(percent.frame.maxX, next.frame.minX, "poster \(id): number runs into the next poster")
            }
        }
    }

    /// John, 2026-11-26: "after reading, it does not get reflected on the
    /// progress bar". With -demoProgress, series 1 (4 chapters) starts
    /// with 2 read and chapter 3 at page 6.
    func testProgressBarUpdatesAfterReading() {
        launch(["-demoProgress"])
        openKavitaLibrary()
        pickOption("libraryOptions.caption.progress")
        XCTAssertTrue(titlePercent.waitForExistence(timeout: 10))
        XCTAssertEqual(titlePercent.label, "50%")
        XCTAssertEqual(titleProgress.value as? String, "50 percent")

        let poster = app.buttons["poster.1"]
        moveFocus(to: poster)
        remote.press(.select)
        let resume = app.buttons["series.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        // The series page says how far along it is (John, 2026-11-26).
        let percentRead = app.staticTexts["series.percentRead"]
        XCTAssertTrue(percentRead.waitForExistence(timeout: 10))
        XCTAssertEqual(percentRead.label, "50% read")
        moveFocus(to: resume)
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["reader.paged"].waitForExistence(timeout: 15))
        // Read to the end of chapter 3 (right to left: Left turns forward).
        let transition = app.descendants(matching: .any)["reader.transition"]
        for _ in 0..<20 where !transition.exists {
            remote.press(.left)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(transition.waitForExistence(timeout: 5), "never reached the end of chapter 3")
        remote.press(.menu) // close the reader
        XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10))
        // The chapter list is current on the first return, not the next
        // one (John, 2026-11-26: it lagged one reader visit behind).
        let chapter3 = app.buttons["chapter.1-3"]
        XCTAssertTrue(chapter3.waitForExistence(timeout: 10))
        wait(chapter3, "value == 'read'", timeout: 10)
        XCTAssertEqual(app.buttons["chapter.1-4"].value as? String, "unread")
        wait(percentRead, "label == '75% read'")
        remote.press(.menu) // back to the grid
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        wait(titlePercent, "label == '75%'", timeout: 15)
        wait(titleProgress, "value == '75 percent'")
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
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
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
