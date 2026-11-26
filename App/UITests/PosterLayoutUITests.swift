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

    /// Every element with `identifier`. Home shows the same series id in
    /// several rows (and once per demo server in merged rows), so ids alone
    /// don't pick one poster; callers pick by position.
    private func all(_ query: XCUIElementQuery, _ identifier: String) -> [XCUIElement] {
        query.matching(identifier: identifier).allElementsBoundByIndex
    }

    /// The title of series `id` that sits right under `cover`.
    private func title(_ id: String, under cover: CGRect) -> XCUIElement? {
        all(app.staticTexts, "poster.title.\(id)")
            .filter { $0.frame.minY >= cover.midY }
            .min(by: { distance($0.frame, cover) < distance($1.frame, cover) })
    }

    /// The poster of series `id` closest to `frame`.
    private func poster(_ id: String, near frame: CGRect) -> XCUIElement? {
        all(app.buttons, "poster.\(id)")
            .min(by: { abs($0.frame.midX - frame.midX) + abs($0.frame.midY - frame.midY)
                     < abs($1.frame.midX - frame.midX) + abs($1.frame.midY - frame.midY) })
    }

    private func distance(_ title: CGRect, _ cover: CGRect) -> CGFloat {
        abs(title.minX - cover.minX) + abs(title.minY - cover.maxY)
    }

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
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        let id = focusFirstPoster()
        let focusedCover = focusedPoster.frame
        guard let label = title(id, under: focusedCover) else { return XCTFail("no title under poster \(id)") }
        let focusedTitleTop = label.frame.minY
        XCTAssertLessThanOrEqual(focusedCover.maxY, focusedTitleTop + 1,
                                 "focused cover \(focusedCover) covers its title \(label.frame)")

        // Move focus to the neighbour; this title drops back under its cover.
        remote.press(.right)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertNotEqual(focusedPoster.frame, focusedCover, "focus didn't move along the shelf")
        guard let resting = poster(id, near: focusedCover) else { return XCTFail("poster \(id) went away") }
        let restingCover = resting.frame
        guard let restingLabel = title(id, under: restingCover) else { return XCTFail("no title under poster \(id)") }
        let restingTitleTop = restingLabel.frame.minY
        let drop = expectedDrop(width: restingCover.width)
        XCTAssertGreaterThanOrEqual(focusedTitleTop - restingTitleTop, drop - 2,
                                    "title only moved \(focusedTitleTop - restingTitleTop) pt on focus, expected \(drop)")
        XCTAssertGreaterThan(restingTitleTop, restingCover.maxY, "resting title sits under its cover")
    }

    /// Titles are allowed two lines. Demo titles like "Lantern Chronicles 3"
    /// don't fit one line of a medium poster, so they must wrap rather than
    /// be cut to one truncated line.
    func testLongTitlesWrapToTwoLines() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        let titles = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.title.'"))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 10))
        let onScreen = titles.allElementsBoundByIndex.filter { $0.frame.width > 0 && $0.frame.minX >= 0 }
        guard let longest = onScreen.max(by: { $0.label.count < $1.label.count }) else {
            return XCTFail("no poster titles on screen")
        }
        XCTAssertGreaterThanOrEqual(longest.label.count, 20, "demo data has no long title on Home: \(longest.label)")
        let id = String(longest.identifier.dropFirst("poster.title.".count))
        let titleFrame = longest.frame
        guard let cover = all(app.buttons, "poster.\(id)")
            .filter({ $0.frame.maxY <= titleFrame.minY + 1 })
            .min(by: { abs($0.frame.minX - titleFrame.minX) + abs($0.frame.maxY - titleFrame.minY)
                     < abs($1.frame.minX - titleFrame.minX) + abs($1.frame.maxY - titleFrame.minY) })?.frame
        else { return XCTFail("no poster above \"\(longest.label)\"") }
        // One line of .caption is 32 pt; two are about 64.
        XCTAssertGreaterThan(titleFrame.height, 50,
                             "\"\(longest.label)\" got one line (\(titleFrame.height) pt) under a \(cover.width) pt poster")
        XCTAssertLessThanOrEqual(titleFrame.width, cover.width + 1, "title wider than its poster")
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

        guard let label = title("1", under: first.frame) else { return XCTFail("no title under poster 1") }
        let below = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.'")).allElementsBoundByIndex
            .filter { $0.identifier != "poster.1" && abs($0.frame.midX - first.frame.midX) < first.frame.width / 2
                      && $0.frame.minY > first.frame.midY }
            .min(by: { $0.frame.minY < $1.frame.minY })
        guard let below else { return XCTFail("no poster under poster 1") }
        XCTAssertLessThanOrEqual(first.frame.maxY, label.frame.minY + 1, "focused cover covers its title")
        XCTAssertLessThan(label.frame.maxY, below.frame.minY,
                          "focused title \(label.frame) runs into \(below.identifier) \(below.frame)")
    }

    /// John (2026-11-26): posters in a row had different heights (one- or
    /// two-line titles), so the lines under them didn't line up. Every
    /// title now takes two lines, so each line under it starts at the same
    /// height across the row.
    func testCaptionLinesLineUpAcrossARow() {
        launch()
        XCTAssertTrue(app.staticTexts["shelf.recentlyUpdated"].waitForExistence(timeout: 15))
        let shelf = app.descendants(matching: .any)["shelfRow.recentlyUpdated"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5) // counts fill in
        let screen = app.windows.firstMatch.frame
        // A focused poster's caption drops on purpose; leave it out.
        let focusedFrame = focusedPoster.exists ? focusedPoster.frame : nil
        func onScreen(_ prefix: String) -> [XCUIElement] {
            shelf.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
                .filter { $0.frame.width > 0 && $0.frame.minX >= 0 && $0.frame.maxX <= screen.maxX }
                .filter { el in focusedFrame.map { abs(el.frame.minX - $0.minX) > $0.width / 2 } ?? true }
        }
        let titles = onScreen("poster.title.")
        XCTAssertGreaterThanOrEqual(titles.count, 3, "not enough posters on screen")
        let heights = titles.map(\.frame.height)
        XCTAssertLessThan(heights.max()! - heights.min()!, 1, "titles take different heights: \(heights)")
        XCTAssertGreaterThan(heights.min()!, 50, "titles don't reserve two lines: \(heights)")
        for prefix in ["poster.title.", "poster.caption.", "poster.server."] {
            let tops = onScreen(prefix).map(\.frame.minY)
            guard let first = tops.first else { continue }
            XCTAssertTrue(tops.allSatisfy { abs($0 - first) < 1 }, "\(prefix) lines don't line up: \(tops)")
        }
    }
}
