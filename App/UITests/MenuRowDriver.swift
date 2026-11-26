import XCTest

/// Drives the value rows of a reader drawer (`ReaderMenu`, `BookReaderMenu`)
/// with the remote, the way a person would. Rows are `<prefix>.<row>` with
/// the current value as their accessibility value; a row with choices opens
/// them in place, as `<prefix>.<row>.<option>`.
///
/// ```swift
/// let menu = MenuRowDriver(app: app, prefix: "reader.menu")
/// menu.pick("layout.single")              // opens Page Layout, picks Single Page
/// menu.expectValue("layout", "Single Page")
/// menu.setToggle("cropBorders", on: true)
/// ```
struct MenuRowDriver {
    let app: XCUIApplication
    let prefix: String
    private let remote = XCUIRemote.shared

    func item(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["\(prefix).\(id)"]
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Moves focus to `id` with the arrows: up/down to its row, then
    /// left/right along it.
    func moveFocus(to id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = item(id)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "No \(prefix).\(id)", file: file, line: line)
        for _ in 0..<30 {
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
        XCTAssertTrue(target.hasFocus, "Couldn't move focus to \(prefix).\(id)", file: file, line: line)
    }

    /// Focuses `id` and clicks it.
    func press(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        moveFocus(to: id, file: file, line: line)
        remote.press(.select)
    }

    /// "row.option": opens the row's choices (unless they're open) and
    /// picks the option, then waits for the rows to come back.
    func pick(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let dot = id.lastIndex(of: ".") else {
            XCTFail("\(id) isn't row.option", file: file, line: line)
            return
        }
        let row = String(id[..<dot])
        if !item(id).exists {
            press(row, file: file, line: line)
            XCTAssertTrue(item(id).waitForExistence(timeout: 5), "\(row) didn't open its choices",
                          file: file, line: line)
            wait(for: "\(row).title", "exists == true", file: file, line: line)
        }
        press(id, file: file, line: line)
        wait(for: id, "exists == false", file: file, line: line)
        wait(for: row, "hasFocus == true", file: file, line: line)
    }

    /// Clicks an On/Off row until it shows `on`.
    func setToggle(_ row: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let want = on ? "On" : "Off"
        guard value(row) != want else { return }
        press(row, file: file, line: line)
        expectValue(row, want, file: file, line: line)
    }

    func value(_ row: String) -> String? {
        item(row).value as? String
    }

    func expectValue(_ row: String, _ value: String, timeout: TimeInterval = 5,
                     file: StaticString = #filePath, line: UInt = #line) {
        let element = item(row)
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(prefix).\(row) shows \"\(element.exists ? (element.value as? String ?? "<none>") : "<missing>")\", expected \"\(value)\"",
                       file: file, line: line)
    }

    func wait(for id: String, _ format: String, timeout: TimeInterval = 5,
              file: StaticString = #filePath, line: UInt = #line) {
        let element = item(id)
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "\(prefix).\(id) never matched \(format)", file: file, line: line)
    }
}
