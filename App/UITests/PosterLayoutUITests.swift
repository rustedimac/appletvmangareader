import XCTest

/// Poster layout against the offline demo servers: a focused poster's
/// title moves clear of the enlarged cover (and stays clear of the next
/// row), and long titles get both of their lines instead of one truncated
/// line. See `SeriesPoster` and `PosterMetrics.focusedTitleDrop`.
final class PosterLayoutUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(tab: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers"] + (tab.map { ["-uiTestingTab", $0] } ?? [])
        app.launch()
    }

    private var focusedPoster: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    }

    private func title(_ id: String) -> XCUIElement { app.staticTexts["poster.title.\(id)"] }

    private func posterID(_ poster: XCUIElement) -> String {
        String(poster.identifier.dropFirst("poster.".count))
    }

    /// Presses down until a poster has focus, lets the focus animation
    /// finish and returns its id.
    private func focusFirstPoster(file: StaticString = #filePath, line: UInt = #line) -> String {
        for _ in 0..<8 where !focusedPoster.exists {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(focusedPoster.exists, "no poster took focus. Focus: \(focusedDescription())", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.8)
        return posterID(focusedPoster)
    }

    /// `PosterMetrics.focusedTitleDrop` for an unfocused poster this wide.
    private func expectedDrop(width: CGFloat) -> CGFloat {
        (width * 1.5 * 0.05).rounded(.up) + 8
    }

    // MARK: Tests

    /// The bug: the first poster of "Recently Updated" grew over its own
    /// title when focused. The title now moves down by the cover's growth
    /// and comes back when focus leaves.
    func testFocusedPosterMovesItsTitleClearOfTheCover() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.Demo Kavita.recentlyUpdated"].waitForExistence(timeout: 15))
        let id = focusFirstPoster()
        let poster = app.buttons["poster.\(id)"], label = title(id)
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        let focusedTitleTop = label.frame.minY
        XCTAssertLessThanOrEqual(poster.frame.maxY, focusedTitleTop + 1,
                                 "focused cover \(poster.frame) covers its title \(label.frame)")

        // Move focus to the neighbour; this title drops back under its cover.
        remote.press(.right)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertNotEqual(posterID(focusedPoster), id, "focus didn't move along the shelf")
        let restingTitleTop = label.frame.minY
        let drop = expectedDrop(width: poster.frame.width)
        XCTAssertGreaterThanOrEqual(focusedTitleTop - restingTitleTop, drop - 2,
                                    "title only moved \(focusedTitleTop - restingTitleTop) pt on focus, expected \(drop)")
        XCTAssertGreaterThan(label.frame.minY, poster.frame.maxY, "resting title sits under its cover")
    }

    /// Titles are allowed two lines. Demo titles like "Lantern Chronicles 3"
    /// don't fit one line of a medium poster, so they must wrap rather than
    /// be cut to one truncated line.
    func testLongTitlesWrapToTwoLines() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.Demo Kavita.recentlyUpdated"].waitForExistence(timeout: 15))
        let titles = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.title.'"))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 10))
        let onScreen = titles.allElementsBoundByIndex.filter { $0.frame.width > 0 && $0.frame.minX >= 0 }
        guard let longest = onScreen.max(by: { $0.label.count < $1.label.count }) else {
            return XCTFail("no poster titles on screen")
        }
        XCTAssertGreaterThanOrEqual(longest.label.count, 20, "demo data has no long title on Home: \(longest.label)")
        let id = String(longest.identifier.dropFirst("poster.title.".count))
        let poster = app.buttons["poster.\(id)"]
        // One line of .caption is 32 pt; two are about 64.
        XCTAssertGreaterThan(longest.frame.height, 50,
                             "\"\(longest.label)\" got one line (\(longest.frame.height) pt) under a \(poster.frame.width) pt poster")
        XCTAssertLessThanOrEqual(longest.frame.width, poster.frame.width + 1, "title wider than its poster")
    }

    /// In a library grid the dropped title of a focused poster still ends
    /// above the poster under it.
    func testFocusedTitleStaysAboveTheNextGridRow() {
        launch(tab: "library")
        let server = app.buttons["library.server.Demo Kavita"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        select(server)
        XCTAssertTrue(app.buttons["poster.1"].waitForExistence(timeout: 10))
        let first = app.buttons["poster.1"]
        focus(first, .down)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(first.hasFocus, "poster 1 never took focus. Focus: \(focusedDescription())")

        let label = title("1")
        XCTAssertTrue(label.exists)
        let below = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.'")).allElementsBoundByIndex
            .filter { $0.identifier != "poster.1" && abs($0.frame.midX - first.frame.midX) < first.frame.width / 2
                      && $0.frame.minY > first.frame.midY }
            .min(by: { $0.frame.minY < $1.frame.minY })
        guard let below else { return XCTFail("no poster under poster 1") }
        XCTAssertLessThanOrEqual(first.frame.maxY, label.frame.minY + 1, "focused cover covers its title")
        XCTAssertLessThan(label.frame.maxY, below.frame.minY,
                          "focused title \(label.frame) runs into \(below.identifier) \(below.frame)")
    }
}
