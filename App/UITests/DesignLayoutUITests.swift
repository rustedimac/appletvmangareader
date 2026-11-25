import XCTest

/// Walks the screens that need no server and checks the measurable rules
/// from docs/DESIGN_GUIDE.md: minimum focus target height, horizontal safe
/// area, form column width and overlapping rows.
///
/// With `DESIGN_AUDIT_DIR` set (pass `TEST_RUNNER_DESIGN_AUDIT_DIR=<dir>` to
/// xcodebuild) it also saves a PNG of every screen to that folder for local
/// review. Never commit those screenshots.
final class DesignLayoutUITests: XCTestCase {
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Screens

    func testProfilePicker() {
        let app = XCUIApplication.launched(seed: "profiles")
        XCTAssertTrue(app.element("profilePicker.manage").waitForExistence(timeout: 10))
        audit(app, "profile-picker")
    }

    func testSettingsScreens() {
        let app = XCUIApplication.launched(seed: "servers", tab: "settings")
        XCTAssertTrue(app.element("settings.addServer").waitForExistence(timeout: 10))
        audit(app, "settings")

        select(app.element("settings.manageProfiles"))
        XCTAssertTrue(app.element("profiles.add").waitForExistence(timeout: 5))
        audit(app, "settings-profiles")

        select(app.element("profiles.add"))
        XCTAssertTrue(app.element("profileEditor.name").waitForExistence(timeout: 5))
        audit(app, "settings-profile-editor")
        back(app, to: "profiles.add")
        back(app, to: "settings.manageProfiles")

        select(app.element("settings.readerDefaults"))
        XCTAssertTrue(app.element("readerDefaults.mode").waitForExistence(timeout: 5))
        audit(app, "settings-reader-defaults")
        back(app, to: "settings.readerDefaults")

        select(app.element("settings.addServer"))
        XCTAssertTrue(app.element("serverEditor.address").waitForExistence(timeout: 5))
        audit(app, "settings-add-server")
        back(app, to: "settings.addServer")

        select(app.element("settings.server.Test Kavita"))
        XCTAssertTrue(app.element("serverEditor.apiKey").waitForExistence(timeout: 5))
        audit(app, "settings-edit-server")
        focus(app.element("serverEditor.remove"))
        audit(app, "settings-edit-server-bottom")
    }

    /// Settings pages keep their title in the left column, so scrolling the
    /// form never leaves the title on top of the rows.
    func testSettingsTitleNeverOverlapsRows() {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.readerDefaults"))
        let first = app.element("readerDefaults.mode")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let title = app.element("settingsPage.title")
        XCTAssertTrue(title.exists, "Default Reader Settings has no settings page title")

        for step in ["top", "bottom", "back-to-top"] {
            if step == "bottom" { focus(app.element("readerDefaults.reset")) }
            if step == "back-to-top" { focus(first, .up) }
            Thread.sleep(forTimeInterval: 0.8)
            audit(app, "settings-reader-defaults-\(step)")
            let form = app.element("settingsPage.form").frame
            XCTAssertLessThanOrEqual(title.frame.maxX, form.minX,
                                     "[\(step)] title \(title.frame) runs into the form \(form)")
        }
        XCTAssertTrue(first.frame.minY > 0, "The first row didn't scroll back into view")
    }

    func testBrowseTabs() {
        for tab in ["home", "library", "favorites", "search"] {
            let app = XCUIApplication.launched(seed: "servers", tab: tab)
            // The seeded servers don't exist, so this shows the error states.
            Thread.sleep(forTimeInterval: 4)
            audit(app, "tab-\(tab)")
            app.terminate()
        }
    }

    func testReader() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"]
        app.launch()
        XCTAssertTrue(app.element("reader.paged").waitForExistence(timeout: 15))
        audit(app, "reader-paged", checkSafeArea: false)
        remote.press(.down)
        XCTAssertTrue(app.element("reader.menu").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        audit(app, "reader-menu-settings")
        let chapters = app.element("reader.menu.tab.chapters")
        focus(app.element("reader.menu.tab.settings"), .up)
        if focus(chapters, .right) {
            remote.press(.select)
            Thread.sleep(forTimeInterval: 0.8)
            audit(app, "reader-menu-chapters")
        }
    }

    // MARK: Checks

    /// Points of slack for focus growth and for system rows whose reported
    /// frame differs slightly from what they draw.
    private let slack: CGFloat = 24
    private let safeSide: CGFloat = 80
    private let minTarget: CGFloat = 60
    private let formColumn: CGFloat = 1000

    private func audit(_ app: XCUIApplication, _ name: String, checkSafeArea: Bool = true,
                       file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: 0.6)
        saveScreenshot(name)

        let screen = app.windows.firstMatch.frame
        guard screen.width > 0 else { return }
        let scale = screen.width / 1920
        let targets = focusables(app, in: screen)

        for (label, frame) in targets {
            // Tab bar items are drawn by the system.
            if frame.minY < 140 * scale { continue }
            // A row cut off by the bottom edge reports only its visible part.
            if frame.maxY > screen.maxY - 4 * scale { continue }
            // A button inside a form row reports only its label's frame;
            // the row around it is what gets focus and what we measure.
            if targets.contains(where: { $0.frame != frame && $0.frame.contains(frame) }) { continue }
            XCTAssertGreaterThanOrEqual(frame.height, minTarget * scale,
                                        "[\(name)] \(label) is \(Int(frame.height / scale)) pt tall (min \(Int(minTarget)))",
                                        file: file, line: line)
            if checkSafeArea {
                XCTAssertGreaterThanOrEqual(frame.minX, (safeSide - slack) * scale,
                                            "[\(name)] \(label) starts at x=\(Int(frame.minX / scale)), inside the 80 pt side margin",
                                            file: file, line: line)
                XCTAssertLessThanOrEqual(frame.maxX, screen.width - (safeSide - slack) * scale,
                                         "[\(name)] \(label) ends at x=\(Int(frame.maxX / scale)), inside the 80 pt side margin",
                                         file: file, line: line)
            }
        }

        // Rows in a settings page stay inside the form column.
        let form = app.element("settingsPage.form")
        if form.exists {
            for cell in form.cells.allElementsBoundByIndex where cell.exists && !cell.frame.isEmpty {
                XCTAssertLessThanOrEqual(cell.frame.width, (formColumn + slack) * scale,
                                         "[\(name)] row \(describe(cell)) is \(Int(cell.frame.width / scale)) pt wide",
                                         file: file, line: line)
            }
        }

        // Rows and buttons must not overlap each other. The system tab bar
        // floats over scrolled content, so leave its items out.
        let inContent = targets.filter { $0.frame.minY >= 140 * scale }
        for i in inContent.indices {
            for j in inContent.indices where j > i {
                let a = inContent[i].frame.insetBy(dx: 2 * scale, dy: 2 * scale)
                let b = inContent[j].frame.insetBy(dx: 2 * scale, dy: 2 * scale)
                // A button inside a row reports its own frame within the row's.
                if a.contains(b) || b.contains(a) { continue }
                XCTAssertFalse(a.intersects(b), "[\(name)] \(inContent[i].label) overlaps \(inContent[j].label)",
                               file: file, line: line)
            }
        }
    }

    /// On-screen focusable elements with their frames.
    private func focusables(_ app: XCUIApplication, in screen: CGRect) -> [(label: String, frame: CGRect)] {
        let queries = [app.cells, app.buttons, app.textFields, app.secureTextFields, app.switches,
                       app.segmentedControls]
        var result: [(String, CGRect)] = []
        for query in queries {
            for element in query.allElementsBoundByIndex {
                guard element.exists else { continue }
                let f = element.frame
                // Only fully visible elements; ones scrolled past the edge are fine.
                guard !f.isEmpty, screen.contains(f) else { continue }
                if result.contains(where: { $0.1 == f }) { continue }
                result.append((describe(element), f))
            }
        }
        return result
    }

    private func describe(_ element: XCUIElement) -> String {
        let id = element.identifier.isEmpty ? element.label : element.identifier
        return "\"\(id)\""
    }

    // MARK: Helpers

    private func back(_ app: XCUIApplication, to id: String) {
        remote.press(.menu)
        XCTAssertTrue(app.element(id).waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func saveScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        // Keep screenshots of passing tests too, for review in the .xcresult.
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["DESIGN_AUDIT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: url.appendingPathComponent("\(name).png"))
    }
}
