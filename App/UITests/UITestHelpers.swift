import XCTest

extension XCUIApplication {
    static func launched(seed: String? = nil, tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-uiTesting"]
        if let seed { args += ["-uiTestingSeed", seed] }
        if let tab { args += ["-uiTestingTab", tab] }
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
func focus(_ element: XCUIElement, _ direction: XCUIRemote.Button = .down, maxPresses: Int = 12,
           file: StaticString = #filePath, line: UInt = #line) -> Bool {
    XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) doesn't exist", file: file, line: line)
    let opposite: XCUIRemote.Button
    switch direction {
    case .down: opposite = .up
    case .up: opposite = .down
    case .left: opposite = .right
    default: opposite = .left
    }
    for d in [direction, opposite] {
        for _ in 0..<maxPresses {
            if isFocused(element) { return true }
            XCUIRemote.shared.press(d)
        }
    }
    let ok = isFocused(element)
    if !ok {
        let focused = XCUIApplication().descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        print("Focused element: \(focused.exists ? focused.debugDescription : "none")")
    }
    XCTAssertTrue(ok, "Couldn't focus \(element)", file: file, line: line)
    return ok
}

/// True when `element` or the row containing it has focus. In a tvOS List
/// the focus lands on the cell, not on the button inside it.
func isFocused(_ element: XCUIElement) -> Bool {
    if element.hasFocus { return true }
    let focused = XCUIApplication().descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    guard focused.exists else { return false }
    let f = focused.frame, e = element.frame
    guard !f.isEmpty, !e.isEmpty else { return false }
    return f.insetBy(dx: -4, dy: -4).contains(e)
}

/// Focuses `element` and clicks it.
func select(_ element: XCUIElement, _ direction: XCUIRemote.Button = .down,
            file: StaticString = #filePath, line: UInt = #line) {
    if focus(element, direction, file: file, line: line) {
        XCUIRemote.shared.press(.select)
    }
}
