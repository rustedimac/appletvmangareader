import XCTest

/// Webtoon auto-scroll on the demo series (`-readerDemo -readerMode
/// webtoon`): Play/Pause starts and stops it, a click stops it, up/down
/// change its speed while it runs, and the speed is in the reader menu.
/// Game controller buttons can't be pressed from XCUITest; their mapping is
/// covered by `GamepadMappingTests` in MangaCore.
final class WebtoonAutoScrollUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerMode", "webtoon"]
        app.launch()
        XCTAssertTrue(indicator.waitForExistence(timeout: 15), "webtoon reader didn't open")
        wait(strip, "value BEGINSWITH 'focused'")
    }

    private var indicator: XCUIElement { app.staticTexts["reader.webtoon.indicator"] }
    private var strip: XCUIElement { element("reader.webtoon.strip") }
    private var badge: XCUIElement { element("reader.webtoon.autoScroll") }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func menuItem(_ id: String) -> XCUIElement { element("reader.menu.\(id)") }

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5,
                      file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(element) never matched \(format); value=\(String(describing: element.exists ? element.value : nil)) label=\(element.exists ? element.label : "<missing>")",
                       file: file, line: line)
    }

    /// The strip's scroll offset, from its accessibility value.
    private var offset: Int {
        let value = strip.value as? String ?? ""
        guard let range = value.range(of: "offset=") else { return -1 }
        return Int(value[range.upperBound...].prefix { $0.isNumber || $0 == "-" }) ?? -1
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Moves focus to a menu control: up/down to its row, then along it.
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

    func testPlayPauseStartsAutoScrollAndAClickStopsIt() {
        XCTAssertFalse(badge.exists)
        let start = offset
        XCTAssertEqual(start, 0)
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "auto-scroll badge should show")
        XCTAssertEqual(badge.label, "Auto-scroll · Speed 3 of 10")
        XCTAssertFalse(element("reader.menu").exists, "Play/Pause no longer opens the menu here")
        Thread.sleep(forTimeInterval: 2)
        let moved = offset
        XCTAssertGreaterThan(moved, start + 40, "the strip should move on its own")

        // A click stops it and does not open the menu.
        remote.press(.select)
        wait(badge, "exists == false")
        XCTAssertFalse(element("reader.menu").exists)
        let stopped = offset
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertLessThanOrEqual(abs(offset - stopped), 1, "the strip stays put once stopped")

        // Play/Pause again starts it, and again stops it.
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.playPause)
        wait(badge, "exists == false")

        // With auto-scroll off, a click opens the menu as before.
        remote.press(.select)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
    }

    func testUpAndDownChangeTheSpeedWhileItRuns() {
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        let before = offset
        remote.press(.down)
        wait(badge, "label == 'Auto-scroll · Speed 4 of 10'")
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.4)
        remote.press(.up)
        wait(badge, "label == 'Auto-scroll · Speed 2 of 10'")
        // Speed clicks change the speed; they don't step a screen at a time.
        XCTAssertLessThan(offset - before, 700, "clicks while auto-scrolling should not jump a screen")
    }

    func testMenuShowsAndChangesTheSpeedAndCanStartIt() {
        remote.press(.select)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        XCTAssertEqual(menuItem("autoScroll.value").label, "Speed 3 of 10")
        choose("autoScroll.faster")
        wait(menuItem("autoScroll.value"), "label == 'Speed 4 of 10'")
        remote.press(.select)
        wait(menuItem("autoScroll.value"), "label == 'Speed 5 of 10'")
        choose("autoScroll.slower")
        wait(menuItem("autoScroll.value"), "label == 'Speed 4 of 10'")

        let before = offset
        choose("autoScroll.start")
        wait(element("reader.menu"), "exists == false")
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "Start closes the menu and starts auto-scroll")
        XCTAssertEqual(badge.label, "Auto-scroll · Speed 4 of 10", "the menu's speed is used")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertGreaterThan(offset, before + 40)
    }

    func testSpeedSetWithTheRemoteShowsInTheMenu() {
        remote.press(.playPause)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        remote.press(.down)
        wait(badge, "label == 'Auto-scroll · Speed 4 of 10'")
        remote.press(.select)
        wait(badge, "exists == false")
        // The menu shows the speed just set (saved for the profile).
        remote.press(.select)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        XCTAssertEqual(menuItem("autoScroll.value").label, "Speed 4 of 10")
    }
}
