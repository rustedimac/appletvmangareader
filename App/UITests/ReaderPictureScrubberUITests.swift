import XCTest

/// Picture controls, split wide pages and the page scrubber, on the demo
/// series (`-readerDemo`). Chapter 1 has 6 pages and page 4 is wide.
final class ReaderPictureScrubberUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(_ extra: [String] = [], expect: String = "1 / 6") {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"] + extra
        app.launch()
        XCTAssertTrue(element("reader.paged").waitForExistence(timeout: 15))
        expectIndicator(expect)
    }

    private func launchVertical(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo", "-readerMode", "webtoon"] + extra
        app.launch()
        XCTAssertTrue(element("reader.webtoon").waitForExistence(timeout: 15))
        expectLabel(webtoonIndicator, "Chapter 1 · 1 / 6")
    }

    private var webtoonIndicator: XCUIElement { app.staticTexts["reader.webtoon.indicator"] }

    private func expectLabel(_ element: XCUIElement, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed,
                       "Expected \"\(text)\", got \"\(element.exists ? element.label : "<missing>")\"",
                       file: file, line: line)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func menuItem(_ id: String) -> XCUIElement { element("reader.menu.\(id)") }
    private func thumb(_ page: Int) -> XCUIElement { element("reader.scrubber.page.\(page)") }
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

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func openMenu() {
        remote.press(.down)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        wait(menuItem("mode"), "hasFocus == true")
    }

    private var menu: MenuRowDriver { MenuRowDriver(app: app, prefix: "reader.menu") }

    /// Up/down to the control's row, then left/right along it.
    private func moveFocus(to id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = menuItem(id)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "No \(id)", file: file, line: line)
        for _ in 0..<40 {
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

    private func openScrubber() {
        openMenu()
        choose("browsePages")
        XCTAssertTrue(element("reader.scrubber").waitForExistence(timeout: 5))
        wait(element("reader.menu"), "exists == false")
    }

    // MARK: Split wide pages

    func testSplitWidePagesRightToLeft() {
        launch(["-readerLayout", "single", "-readerSplitWide", "YES", "-readerDirection", "rightToLeft"])
        remote.press(.left)
        expectIndicator("2 / 6")
        remote.press(.left)
        expectIndicator("3 / 6")
        // The wide page 4: right half first in right-to-left reading.
        remote.press(.left)
        expectIndicator("4 / 6 · Right half")
        XCTAssertTrue(element("reader.page.3.right").waitForExistence(timeout: 5))
        remote.press(.left)
        expectIndicator("4 / 6 · Left half")
        XCTAssertTrue(element("reader.page.3.left").waitForExistence(timeout: 5))
        remote.press(.left)
        expectIndicator("5 / 6")
        // And back.
        remote.press(.right)
        expectIndicator("4 / 6 · Left half")
    }

    func testSplitToggleInMenu() {
        launch(["-readerLayout", "single", "-readerStartPage", "3", "-readerDirection", "leftToRight"],
               expect: "4 / 6")
        openMenu()
        menu.setToggle("splitWidePages", on: true)
        remote.press(.menu)
        wait(element("reader.menu"), "exists == false")
        expectIndicator("4 / 6 · Left half")
        remote.press(.right)
        expectIndicator("4 / 6 · Right half")
    }

    // MARK: Picture controls

    func testPictureControlsApplyAndReset() {
        launch()
        openMenu()
        XCTAssertEqual(menuItem("picture.brightness.value").label, "0")
        choose("picture.brightness.decrease")
        wait(menuItem("picture.brightness.value"), "label == '−10%'")
        wait(element("reader.page.0"), "value == 'loaded, adjusted'")
        choose("picture.contrast.increase")
        wait(menuItem("picture.contrast.value"), "label == '110%'")
        menu.pick("picture.color.inverted")
        menu.expectValue("picture.color", "Night (Invert)")
        menu.pick("picture.upscaling.lanczos")
        menu.expectValue("picture.upscaling", "Sharp (Lanczos)")
        choose("picture.reset")
        wait(menuItem("picture.brightness.value"), "label == '0'")
        menu.expectValue("picture.color", "Normal")
        menu.expectValue("picture.upscaling", "Standard")
        wait(element("reader.page.0"), "value == 'loaded'")
    }

    func testVerticalReaderOffersColorButNotSharpen() {
        launchVertical()
        // The vertical reader opens its menu with a click.
        remote.press(.select)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        XCTAssertTrue(menuItem("picture.brightness.value").waitForExistence(timeout: 5))
        XCTAssertTrue(menuItem("picture.color").exists)
        XCTAssertFalse(menuItem("picture.sharpen").exists)
        XCTAssertFalse(menuItem("picture.upscaling").exists)
    }

    // MARK: Page scrubber

    func testScrubberJumpsToAPage() {
        launch(["-readerLayout", "single", "-readerDirection", "leftToRight"])
        openScrubber()
        wait(thumb(0), "hasFocus == true")
        XCTAssertEqual(element("reader.scrubber.label").label, "Page 1 of 6")
        remote.press(.right)
        wait(thumb(1), "hasFocus == true")
        wait(element("reader.scrubber.label"), "label == 'Page 2 of 6'")
        // Down jumps 10 pages forward, clamped to the last page.
        remote.press(.down)
        wait(thumb(5), "hasFocus == true")
        wait(element("reader.scrubber.label"), "label == 'Page 6 of 6'")
        // Up jumps 10 back, clamped to the first.
        remote.press(.up)
        wait(thumb(0), "hasFocus == true")
        remote.press(.right)
        remote.press(.right)
        wait(thumb(2), "hasFocus == true")
        remote.press(.select)
        wait(element("reader.scrubber"), "exists == false")
        expectIndicator("3 / 6")
        // The page has focus again: turning works.
        remote.press(.right)
        expectIndicator("4 / 6")
    }

    func testScrubberRunsRightToLeftForManga() {
        launch(["-readerDirection", "rightToLeft"])
        openScrubber()
        wait(thumb(0), "hasFocus == true")
        // Page 1 sits to the right of page 2.
        XCTAssertGreaterThan(thumb(0).frame.minX, thumb(1).frame.minX)
        // Left moves forward, like turning a page.
        remote.press(.left)
        wait(thumb(1), "hasFocus == true")
        // Menu closes it without moving.
        remote.press(.menu)
        wait(element("reader.scrubber"), "exists == false")
        XCTAssertTrue(element("reader.paged").exists)
        expectIndicator("1 / 6")
    }

    func testScrubberInVerticalReader() {
        launchVertical(["-readerDirection", "leftToRight"])
        remote.press(.select)
        XCTAssertTrue(element("reader.menu").waitForExistence(timeout: 5))
        choose("browsePages")
        XCTAssertTrue(element("reader.scrubber").waitForExistence(timeout: 5))
        wait(thumb(0), "hasFocus == true")
        remote.press(.right)
        remote.press(.right)
        wait(thumb(2), "hasFocus == true")
        remote.press(.select)
        wait(element("reader.scrubber"), "exists == false")
        expectLabel(webtoonIndicator, "Chapter 1 · 3 / 6")
    }
}
