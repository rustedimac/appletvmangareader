import XCTest

/// The reader options on iPhone (sheet) and iPad (popover): every row keeps
/// the iOS form margin from the panel's edges, and no section leaves a big
/// blank gap before the next (John, 2026-11-28: rows touched the edges and
/// the Controls legend left a large empty space).
final class ReaderOptionsLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private static let minSideInset: CGFloat = 16
    private static let maxGap: CGFloat = 44

    private func openOptions(_ extra: [String], panel id: String) -> XCUIElement {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-readerDemo"] + extra
        app.launch()
        let options = app.buttons["reader.chrome.options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15), "No options button:\n\(app.debugDescription)")
        options.tap()
        let panel = app.descendants(matching: .any)[id]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Options didn't open")
        sleep(1)  // let the sheet / popover settle
        return panel
    }

    /// Checks what's on screen, scrolls, and checks again to the bottom.
    private func checkLayout(of panel: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // The sheet / popover's own edges (a container's accessibility frame
        // is only the union of its children).
        let edges = app.descendants(matching: .any)["reader.options.panel"]
        XCTAssertTrue(edges.waitForExistence(timeout: 5), "No panel marker", file: file, line: line)
        // The panel itself fits the screen (a too-wide panel pushed rows
        // past the sheet's left edge, where the inset check can't see it).
        let window: CGRect = app.windows.firstMatch.frame
        let marker: CGRect = edges.frame
        XCTAssertGreaterThanOrEqual(marker.minX, window.minX, "Panel starts left of the screen: \(marker)", file: file, line: line)
        XCTAssertLessThanOrEqual(marker.maxX, window.maxX, "Panel ends right of the screen: \(marker)", file: file, line: line)
        var lastSignature = ""
        for _ in 0..<10 {
            let bounds: CGRect = edges.frame
            let elements: [XCUIElement] = panel.buttons.allElementsBoundByIndex + panel.staticTexts.allElementsBoundByIndex
            let frames: [CGRect] = elements.filter { $0.exists }.map { $0.frame }.filter { (f: CGRect) -> Bool in
                guard f.width > 1, f.height > 1 else { return false }
                return bounds.intersection(f).height >= f.height * 0.9
            }
            for f in frames {
                XCTAssertGreaterThanOrEqual(f.minX - bounds.minX, Self.minSideInset,
                                            "Element at \(f) is \(f.minX - bounds.minX) pt from the panel's leading edge", file: file, line: line)
                XCTAssertGreaterThanOrEqual(bounds.maxX - f.maxX, Self.minSideInset,
                                            "Element at \(f) is \(bounds.maxX - f.maxX) pt from the panel's trailing edge", file: file, line: line)
            }
            // Vertical gaps between consecutive rows of content.
            let rows = frames.sorted { $0.minY < $1.minY }
            var bottom: CGFloat?
            for f in rows {
                if let b = bottom, f.minY > b {
                    XCTAssertLessThanOrEqual(f.minY - b, Self.maxGap,
                                             "Blank gap of \(f.minY - b) pt above the element at \(f)", file: file, line: line)
                }
                bottom = max(bottom ?? f.maxY, f.maxY)
            }
            let signature = rows.map { "\(Int($0.minY))" }.joined(separator: ",")
            if signature == lastSignature { break }  // reached the bottom
            lastSignature = signature
            panel.swipeUp()
            sleep(1)
        }
    }

    func testPagedOptionsLayout() {
        checkLayout(of: openOptions([], panel: "reader.menu"))
    }

    func testVerticalOptionsLayout() {
        checkLayout(of: openOptions(["-readerMode", "webtoon"], panel: "reader.menu"))
    }

    func testBookOptionsLayout() {
        checkLayout(of: openOptions(["-readerBook"], panel: "book.menu"))
    }
}
