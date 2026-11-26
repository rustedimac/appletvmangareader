import XCTest

/// "Mark as Read" / "Mark as Unread" from a chapter's long-press menu, its
/// "…" options button (no long press needed), the series "More" menu, and
/// a poster's long-press menu. Runs against the demo servers
/// with `-demoProgress`, so every series starts with chapters 1 and 2 read
/// and chapter 3 at page 6.
final class MarkUnreadUITests: XCTestCase {
    var app: XCUIApplication!
    let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers", "-demoProgress"]
        app.launch()
    }

    // MARK: Helpers

    private var focusedPoster: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @discardableResult
    private func press(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            usleep(350_000)
        }
        return element.exists && element.hasFocus
    }

    /// A menu item by identifier, or by title when the menu doesn't carry
    /// identifiers through.
    private func menuItem(_ identifier: String, _ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", identifier, title)).firstMatch
    }

    /// Focus and element tree, for failure messages.
    private var screen: String {
        "focused: \(focusedDescription())\n" + String(app.debugDescription.prefix(6000))
    }

    private func longPressSelect() {
        remote.press(.select, forDuration: 1.5)
    }

    /// Focuses a poster on Home and returns its series id.
    private func focusHomePoster() -> String {
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        XCTAssertTrue(press(.down, until: focusedPoster, max: 6), "no poster took focus")
        let id = String(focusedPoster.identifier.dropFirst("poster.".count))
        XCTAssertFalse(id.isEmpty)
        return id
    }

    private func openFirstHomeSeries() -> String {
        let id = focusHomePoster()
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["chapter.\(id)-1"].waitForExistence(timeout: 10))
        return id
    }

    private func chapter(_ series: String, _ n: Int) -> XCUIElement {
        app.buttons["chapter.\(series)-\(n)"]
    }

    // MARK: Tests

    func testMarkChapterAsUnreadFromLongPress() {
        let id = openFirstHomeSeries()
        XCTAssertEqual(chapter(id, 1).value as? String, "read")
        XCTAssertEqual(chapter(id, 2).value as? String, "read")

        focus(chapter(id, 2))
        longPressSelect()
        let item = menuItem("chapter.menu.unread", "Mark as Unread")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "chapter menu didn't open. \(screen)")
        select(item)

        XCTAssertTrue(waitFor(chapter(id, 2), "value == 'unread'"), "chapter 2 still shows as read")
        XCTAssertEqual(chapter(id, 1).value as? String, "read", "other chapters keep their state")
        XCTAssertEqual(chapter(id, 3).value as? String, "in progress")
        // The main button still resumes the chapter in progress, as
        // Kavita's continue point does (docs/PROGRESS_SYNC.md).
        XCTAssertTrue(waitFor(app.buttons["series.continue"], "label CONTAINS 'Chapter 3'"))
    }

    func testMarkSeriesAsUnreadFromChapterLongPress() {
        let id = openFirstHomeSeries()
        focus(chapter(id, 1))
        longPressSelect()
        let item = menuItem("chapter.menu.seriesUnread", "Mark Series as Unread")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "chapter menu didn't open. \(screen)")
        select(item)

        for n in 1...3 {
            XCTAssertTrue(waitFor(chapter(id, n), "value == 'unread'"), "chapter \(n) still has progress")
        }
        XCTAssertTrue(waitFor(app.buttons["series.continue"], "label == 'Start Reading'"))
    }

    func testMarkSeriesAsUnreadFromMoreMenu() {
        let id = openFirstHomeSeries()
        let more = app.buttons["series.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(more, .right), "More button should be focusable. \(screen)")
        remote.press(.select)
        let item = menuItem("series.more.unread", "Mark Series as Unread")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "More menu didn't open")
        select(item)

        for n in 1...3 {
            XCTAssertTrue(waitFor(chapter(id, n), "value == 'unread'"), "chapter \(n) still has progress")
        }
        XCTAssertTrue(waitFor(app.buttons["series.continue"], "label == 'Start Reading'"))
    }

    func testMarkSeriesAsUnreadFromPosterLongPress() {
        let id = focusHomePoster()
        longPressSelect()
        let item = menuItem("poster.menu.seriesUnread", "Mark Series as Unread")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "poster menu didn't open. \(screen)")
        select(item)
        XCTAssertTrue(waitFor(item, "exists == false"), "menu didn't close")
        // Give the demo server's round trip a moment, then open the series.
        sleep(1)
        // The series can sit in more than one Home row (Continue Reading and
        // Recently Updated), so look for the focused copy rather than one
        // unique element.
        let poster = app.buttons.matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", "poster.\(id)")).firstMatch
        if !poster.exists { press(.down, until: poster, max: 2) }
        XCTAssertTrue(poster.exists, "poster \(id) lost focus. \(screen)")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10))
        for n in 1...3 {
            XCTAssertTrue(waitFor(chapter(id, n), "value == 'unread'"), "chapter \(n) still has progress")
        }
    }

    // MARK: Mark as read, and the options button

    private func optionsButton(_ series: String, _ n: Int) -> XCUIElement {
        app.descendants(matching: .any)["chapterOptions.\(series)-\(n)"]
    }

    /// Opens a chapter's "…" menu with clicks only.
    private func openOptions(_ series: String, _ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        focus(chapter(series, n), file: file, line: line)
        XCTAssertTrue(focus(optionsButton(series, n), .right), "… button not reachable. \(screen)", file: file, line: line)
        remote.press(.select)
    }

    func testMarkChapterAsReadFromOptionsButton() {
        let id = openFirstHomeSeries()
        XCTAssertEqual(chapter(id, 3).value as? String, "in progress")
        openOptions(id, 3)
        let item = menuItem("chapter.actions.read", "Mark as Read")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "chapter options didn't open. \(screen)")
        select(item)

        XCTAssertTrue(waitFor(chapter(id, 3), "value == 'read'"), "chapter 3 should show as read")
        XCTAssertEqual(chapter(id, 1).value as? String, "read")
        XCTAssertFalse(app.buttons["series.continue"].label.contains("Chapter 3"),
                       "Continue moves past a chapter marked read")
    }

    func testMarkUnreadFromOptionsThenMarkPreviousReadFromLongPress() {
        let id = openFirstHomeSeries()
        openOptions(id, 1)
        let unread = menuItem("chapter.actions.unread", "Mark as Unread")
        XCTAssertTrue(unread.waitForExistence(timeout: 5), "chapter options didn't open. \(screen)")
        select(unread)
        XCTAssertTrue(waitFor(chapter(id, 1), "value == 'unread'"), "chapter 1 should show as unread")

        // Focus is still on chapter 1's "…" button: go down that column,
        // then left onto the chapter itself.
        focus(optionsButton(id, 3), .down)
        XCTAssertTrue(focus(chapter(id, 3), .left), "chapter 3 not reachable. \(screen)")
        longPressSelect()
        let previous = menuItem("chapter.menu.previousRead", "Mark Previous as Read")
        XCTAssertTrue(previous.waitForExistence(timeout: 5), "long-press menu didn't offer it. \(screen)")
        select(previous)
        XCTAssertTrue(waitFor(chapter(id, 1), "value == 'read'"), "chapter 1 should be read again")
        XCTAssertEqual(chapter(id, 2).value as? String, "read")
        XCTAssertEqual(chapter(id, 3).value as? String, "in progress", "the chapter itself is left as it was")
    }

    func testMarkSeriesAsReadFromMoreMenu() {
        let id = openFirstHomeSeries()
        let more = app.buttons["series.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(more, .right), "More button should be focusable. \(screen)")
        remote.press(.select)
        let item = menuItem("series.more.read", "Mark Series as Read")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "More menu didn't open")
        select(item)
        for n in 1...3 {
            XCTAssertTrue(waitFor(chapter(id, n), "value == 'read'"), "chapter \(n) should be read")
        }
        XCTAssertTrue(waitFor(app.buttons["series.continue"], "label == 'Read Again'"))
    }
}
