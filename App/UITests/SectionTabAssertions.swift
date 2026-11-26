import XCTest

// Kept out of UITestHelpers.swift: CI runs the full UI suite for any change
// there (tools/select_ui_tests.py).

/// Checks a `SectionTabBar` is laid out like the top tab bar: the tabs sit
/// side by side on one line inside the track, none wraps (all the same
/// height, no taller than one line plus focus growth), they don't overlap,
/// they carry no images (no radio rings or checkmarks), and the track fits
/// inside the screen's side margin.
func assertSectionTabLayout(_ app: XCUIApplication, track trackID: String, tabs tabIDs: [String],
                            titles: [String], file: StaticString = #filePath, line: UInt = #line) {
    let track = app.descendants(matching: .any)[trackID]
    XCTAssertTrue(track.waitForExistence(timeout: 5), "No \(trackID)", file: file, line: line)
    let screen = app.windows.firstMatch.frame
    let scale = screen.width / 1920
    let trackFrame = track.frame
    let tabs = tabIDs.map { app.descendants(matching: .any)[$0] }
    var previous: CGRect?
    for (i, tab) in tabs.enumerated() {
        XCTAssertTrue(tab.exists, "No \(tabIDs[i])", file: file, line: line)
        let f = tab.frame
        XCTAssertEqual(tab.label, titles[i], "\(tabIDs[i]) label", file: file, line: line)
        // One line of callout text in a 66 pt target, plus up to ~5 % focus growth.
        XCTAssertLessThanOrEqual(f.height, 76 * scale,
                                 "\(tabIDs[i]) is \(Int(f.height / scale)) pt tall: its label wrapped",
                                 file: file, line: line)
        XCTAssertGreaterThanOrEqual(f.height, 60 * scale, "\(tabIDs[i]) is too short to focus",
                                    file: file, line: line)
        XCTAssertTrue(trackFrame.insetBy(dx: -6 * scale, dy: -6 * scale).contains(f),
                      "\(tabIDs[i]) \(f) sticks out of the track \(trackFrame)", file: file, line: line)
        if let p = previous {
            XCTAssertEqual(f.midY, p.midY, accuracy: 4 * scale, "tabs aren't on one line", file: file, line: line)
            XCTAssertGreaterThanOrEqual(f.minX, p.maxX - 4 * scale, "\(tabIDs[i]) overlaps the tab before it",
                                        file: file, line: line)
        }
        previous = f
    }
    XCTAssertEqual(track.images.count, 0, "tabs must be text only (no radio rings or checkmarks)",
                   file: file, line: line)
    XCTAssertLessThanOrEqual(trackFrame.maxX, screen.maxX - 56 * scale,
                             "the tab track runs into the right-hand safe margin", file: file, line: line)
}
