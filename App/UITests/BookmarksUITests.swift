import XCTest

/// Page bookmarks: toggling from the reader (menu button and pressing up),
/// the reader menu's Bookmarks tab, the Bookmarks tab and series detail.
final class BookmarksUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private var indicator: XCUIElement { app.staticTexts["reader.pageIndicator"] }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 8,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format)", file: file, line: line)
    }

    private func expectIndicator(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        wait(indicator, "label == '\(text)'", file: file, line: line)
    }

    /// Moves focus by geometry until `target` has it, then clicks.
    private func choose(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(target.waitForExistence(timeout: 8), "\(target) missing", file: file, line: line)
        var stuck = false
        for _ in 0..<25 {
            if isFocused(target) { break }
            let current = focused
            guard current.exists else { remote.press(.down); Thread.sleep(forTimeInterval: 0.35); continue }
            let a = current.frame, b = target.frame
            let vertical = b.midY > a.maxY || b.midY < a.minY
            // When a vertical move goes nowhere (no control straight above or
            // below), slide sideways toward the target first.
            if vertical && !stuck {
                remote.press(b.midY > a.maxY ? .down : .up)
            } else if b.midX > a.midX {
                remote.press(.right)
            } else {
                remote.press(.left)
            }
            Thread.sleep(forTimeInterval: 0.35)
            stuck = vertical && !stuck && focused.frame == a
        }
        XCTAssertTrue(isFocused(target), "Couldn't focus \(target). Focus: \(focusedDescription())", file: file, line: line)
        remote.press(.select)
    }

    private func launchReader() {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"]
        app.launch()
        XCTAssertTrue(element("reader.paged").waitForExistence(timeout: 15))
        expectIndicator("1 / 6")
    }

    private func openMenu() {
        remote.press(.down)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        wait(element("reader.menu.mode.paged"), "hasFocus == true")
    }

    private func closeMenu() {
        remote.press(.menu)
        wait(element("reader.menu"), "exists == false")
    }

    // MARK: Reader

    func testPressUpBookmarksThePageAndAgainRemovesIt() {
        launchReader()
        XCTAssertFalse(element("reader.bookmarked").exists)
        remote.press(.up)
        wait(element("reader.notice"), "label == 'Bookmarked page 1'")
        XCTAssertTrue(element("reader.bookmarked").waitForExistence(timeout: 5))

        // The ribbon follows the page.
        remote.press(.left)
        expectIndicator("2–3 / 6")
        wait(element("reader.bookmarked"), "exists == false")
        remote.press(.right)
        expectIndicator("1 / 6")
        XCTAssertTrue(element("reader.bookmarked").waitForExistence(timeout: 5))

        remote.press(.up)
        wait(element("reader.notice"), "label == 'Bookmark removed'")
        wait(element("reader.bookmarked"), "exists == false")
    }

    func testMenuButtonAndBookmarksTabJumpToPage() {
        launchReader()
        // Bookmark the wide page 4 from the menu.
        remote.press(.left)
        expectIndicator("2–3 / 6")
        remote.press(.left)
        expectIndicator("4 / 6")
        openMenu()
        let button = element("reader.menu.bookmark")
        XCTAssertEqual(button.value as? String, "off")
        choose(button)
        wait(button, "value == 'on'")
        closeMenu()
        XCTAssertTrue(element("reader.bookmarked").waitForExistence(timeout: 5))

        // Go back to the start, then jump to the bookmark from the menu.
        remote.press(.right)
        remote.press(.right)
        expectIndicator("1 / 6")
        openMenu()
        choose(element("reader.menu.tab.bookmarks"))
        let row = element("reader.menu.bookmark.demo-1.3")
        choose(row)
        wait(element("reader.menu"), "exists == false")
        expectIndicator("4 / 6")
        XCTAssertTrue(element("reader.bookmarked").exists)
    }

    func testBookmarkInAnotherChapterOpensThatChapter() {
        launchReader()
        remote.press(.up)  // bookmark chapter 1, page 1
        XCTAssertTrue(element("reader.bookmarked").waitForExistence(timeout: 5))
        openMenu()
        choose(element("reader.menu.tab.chapters"))
        choose(element("reader.menu.chapter.demo-3"))
        wait(element("reader.menu"), "exists == false")
        expectIndicator("1 / 4")
        XCTAssertFalse(element("reader.bookmarked").exists)

        openMenu()
        choose(element("reader.menu.tab.bookmarks"))
        choose(element("reader.menu.bookmark.demo-1.0"))
        expectIndicator("1 / 6")
        XCTAssertTrue(element("reader.bookmarked").waitForExistence(timeout: 5))
    }

    func testWebtoonMenuBookmark() {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerMode", "webtoon"]
        app.launch()
        XCTAssertTrue(element("reader.webtoon").waitForExistence(timeout: 15))
        remote.press(.select)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        let button = element("reader.menu.bookmark")
        choose(button)
        wait(button, "value == 'on'")
        choose(element("reader.menu.tab.bookmarks"))
        XCTAssertTrue(element("reader.menu.bookmark.demo-1.0").waitForExistence(timeout: 5))
    }

    // MARK: Library

    private func launchLibrary(tab: String) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers", "-demoFavorites", "-uiTestingTab", tab]
        app.launch()
    }

    func testBookmarksTabListsAndOpensBookmarks() {
        launchLibrary(tab: "bookmarks")
        let row = element("bookmark.1-2.4")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(element("bookmark.2-1.0").exists)
        XCTAssertTrue(element("bookmarks.series.1").exists)
        choose(row)
        XCTAssertTrue(element("reader.paged").waitForExistence(timeout: 15))
        // Page 5 sits in the spread 4–5 (the cover is alone).
        expectIndicator("4–5 / 20")
        XCTAssertTrue(element("reader.bookmarked").waitForExistence(timeout: 5))
    }

    func testSeriesDetailShowsBookmarks() {
        launchLibrary(tab: "favorites")
        let poster = app.buttons["poster.1"]
        choose(poster)
        XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("series.bookmarks").waitForExistence(timeout: 10))
        let card = element("series.bookmark.1-2.4")
        XCTAssertTrue(card.exists)
        choose(card)
        XCTAssertTrue(element("reader.paged").waitForExistence(timeout: 15))
        expectIndicator("4–5 / 20")
    }
}
