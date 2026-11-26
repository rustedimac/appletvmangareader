import XCTest

extension XCUIApplication {
    static func launched(seed: String? = nil, tab: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-uiTesting"]
        if let seed { args += ["-uiTestingSeed", seed] }
        if let tab { args += ["-uiTestingTab", tab] }
        args += extra
        app.launchArguments = args
        app.launch()
        return app
    }

    /// Any element with this accessibility identifier or label.
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }
}

/// Moves focus with the Siri Remote until `element` has it. Tries `direction`
/// first, then the opposite way, so tests don't depend on where focus starts.
@discardableResult
func focus(_ element: XCUIElement, _ direction: XCUIRemote.Button = .down, maxPresses: Int = 10,
           file: StaticString = #filePath, line: UInt = #line) -> Bool {
    XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) doesn't exist", file: file, line: line)
    let opposite: XCUIRemote.Button
    switch direction {
    case .down: opposite = .up
    case .up: opposite = .down
    case .left: opposite = .right
    default: opposite = .left
    }
    var trail: [String] = []
    for d in [direction, opposite] {
        for _ in 0..<maxPresses {
            // Let the focus animation settle before reading focus.
            Thread.sleep(forTimeInterval: 0.4)
            if isFocused(element) { return true }
            trail.append(focusedDescription())
            XCUIRemote.shared.press(d)
        }
    }
    Thread.sleep(forTimeInterval: 0.4)
    let ok = isFocused(element)
    XCTAssertTrue(ok, "Couldn't focus \(element) frame=\(element.frame). Focus trail: \(trail.joined(separator: " > "))",
                  file: file, line: line)
    return ok
}

func focusedDescription() -> String {
    let all = XCUIApplication().descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
    return all.map { "\($0.identifier.isEmpty ? $0.label : $0.identifier)@\(Int($0.frame.minY))" }.joined(separator: "+")
}

/// True when `element` or the row containing it has focus. In a tvOS List
/// the focus lands on the cell, not on the button inside it.
func isFocused(_ element: XCUIElement) -> Bool {
    if element.hasFocus { return true }
    if !element.identifier.isEmpty,
       XCUIApplication().descendants(matching: .any)
           .matching(NSPredicate(format: "hasFocus == true AND identifier == %@", element.identifier)).count > 0 {
        return true
    }
    let focused = XCUIApplication().descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    guard focused.exists else { return false }
    let f = focused.frame, e = element.frame
    guard !f.isEmpty, !e.isEmpty else { return false }
    // The cell and the button inside it don't line up exactly, so compare
    // the button's center against the focused cell.
    return f.contains(CGPoint(x: e.midX, y: e.midY))
}

/// Focuses `element` and clicks it.
func select(_ element: XCUIElement, _ direction: XCUIRemote.Button = .down,
            file: StaticString = #filePath, line: UInt = #line) {
    if focus(element, direction, file: file, line: line) {
        XCUIRemote.shared.press(.select)
    }
}

/// Moves focus down onto the first poster that takes it, opens it, waits
/// for the series screen and returns the series id (without "poster.").
@discardableResult
func openFocusedPoster(_ app: XCUIApplication, maxPresses: Int = 6,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
    let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.' AND hasFocus == true")).firstMatch
    var presses = 0
    while !focused.exists && presses < maxPresses {
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.5)
        presses += 1
    }
    XCTAssertTrue(focused.exists, "no poster took focus", file: file, line: line)
    let id = String(focused.identifier.dropFirst("poster.".count))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.staticTexts["series.title"].waitForExistence(timeout: 10), file: file, line: line)
    return id
}

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
