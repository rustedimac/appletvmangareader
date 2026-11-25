import XCTest

/// Top Shelf items open `mangareader://` links. These launch with
/// `-uiTestingOpenLink`, which routes a link the same way `onOpenURL` does.
final class TopShelfLinkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(link: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers", "-uiTestingOpenLink", link] + extra
        app.launch()
        return app
    }

    func testSeriesLinkOpensSeriesPage() {
        let app = launch(link: "series:Demo Kavita:3")
        let title = app.element("series.title")
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Lantern Chronicles 3")
        // Menu goes back to the app.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
    }

    func testReadLinkOpensReaderThenMenuReturns() {
        let app = launch(link: "read:Demo Kavita:3:3-2")
        let reader = app.element("reader.paged")
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
    }

    func testLinkSkipsWhosReading() {
        let app = launch(link: "series:Demo Kavita:3", extra: ["-uiTestingSeed", "profiles"])
        XCTAssertTrue(app.element("series.title").waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Who's reading?"].exists)
    }

    /// "pins": Me asks for PIN 1111 to open. A Top Shelf link into Me must
    /// ask too, and opens once it's entered.
    func testLinkIntoProfileWithPINAsksForIt() {
        let app = launch(link: "series:Demo Kavita:3", extra: ["-uiTestingSeed", "pins"])
        let title = app.element("pin.title")
        XCTAssertTrue(title.waitForExistence(timeout: 15), "the link didn't ask for the PIN")
        XCTAssertEqual(title.label, "Enter Me's PIN")
        XCTAssertFalse(app.element("series.title").exists)

        XCTAssertTrue(focus(app.element("pin.key.1"), .right))
        for _ in 0..<4 {
            XCUIRemote.shared.press(.select)
            usleep(300_000)
        }
        XCTAssertTrue(app.element("series.title").waitForExistence(timeout: 15), "right PIN didn't open the link")
    }

    /// "filtered" hides Horror (demo series 5). Its link must not open it.
    func testLinkToHiddenSeriesDoesNotOpenIt() {
        let app = launch(link: "series:Demo Kavita:5", extra: ["-uiTestingSeed", "filtered"])
        XCTAssertTrue(app.staticTexts["Couldn't open this series"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.element("series.title").exists)
    }
}
