import XCTest

/// Favorites sort bar, against the demo favorites seeded by
/// `-demoFavorites` (see `AppModel.installDemoFavoritesAndBookmarks`):
/// series 1–4 are Ember, Harbor, Lantern and Meadow Chronicles.
final class FavoritesSortUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoServers", "-demoFavorites", "-uiTestingTab", "favorites"]
        app.launch()
        XCTAssertTrue(app.buttons["favorites.sort.title"].waitForExistence(timeout: 15))
    }

    /// Series ids of the grid's posters, left to right, top to bottom.
    private var posterOrder: String {
        let grid = app.descendants(matching: .any)["favorites.grid"]
        let posters = grid.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster.'")).allElementsBoundByIndex
        return posters
            .map { ($0.frame, String($0.identifier.dropFirst("poster.".count))) }
            .sorted { ($0.0.minY.rounded(), $0.0.minX) < ($1.0.minY.rounded(), $1.0.minX) }
            .map(\.1)
            .joined()
    }

    private func expectOrder(_ order: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(8)
        while posterOrder != order, Date() < deadline { Thread.sleep(forTimeInterval: 0.3) }
        let modelOrder = (app.descendants(matching: .any)["favorites.grid"].value as? String) ?? "?"
        XCTAssertEqual(posterOrder, order,
                       "model order \(modelOrder), sort \(app.buttons["favorites.sort.direction"].value ?? "?")",
                       file: file, line: line)
    }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Moves focus by geometry: down into the sort bar, then along it.
    private func choose(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = app.buttons[id]
        XCTAssertTrue(target.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<20 {
            if target.hasFocus { break }
            let a = focused.frame, b = target.frame
            if !focused.exists || b.midY > a.maxY { remote.press(.down) }
            else if b.midY < a.minY { remote.press(.up) }
            else if b.midX > a.midX { remote.press(.right) }
            else { remote.press(.left) }
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(target.hasFocus, "Couldn't focus \(id). Focus: \(focusedDescription())", file: file, line: line)
        // Let the bar's scroll and focus animation finish, or the click can be dropped.
        Thread.sleep(forTimeInterval: 0.8)
        // A click either selects a new key or flips the direction. If neither
        // shows up, the click was dropped: press again.
        let before = sortState
        for _ in 0..<3 {
            remote.press(.select)
            let deadline = Date().addingTimeInterval(3)
            while sortState == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            if sortState != before { break }
        }
        XCTAssertNotEqual(sortState, before, "Pressing \(id) changed nothing", file: file, line: line)
    }

    /// The selected sort key and direction, as the sort bar shows them.
    private var sortState: String {
        let keys = ["dateFavorited", "title", "latestChapter", "lastRead", "unread", "server"]
        let selected = keys.first { app.buttons["favorites.sort.\($0)"].isSelected } ?? "?"
        let direction = (app.buttons["favorites.sort.direction"].value as? String) ?? "?"
        return "\(selected) \(direction)"
    }

    func testDefaultIsNewestFavoritedFirst() {
        XCTAssertTrue(app.buttons["favorites.sort.dateFavorited"].isSelected)
        XCTAssertEqual(app.buttons["favorites.sort.direction"].value as? String, "descending")
        expectOrder("2413")
    }

    func testEachSortOption() {
        choose("favorites.sort.title")
        XCTAssertTrue(app.buttons["favorites.sort.title"].isSelected)
        expectOrder("1234")
        choose("favorites.sort.latestChapter")
        expectOrder("4231")
        choose("favorites.sort.lastRead")
        expectOrder("3124")
        choose("favorites.sort.unread")
        expectOrder("3412")
        choose("favorites.sort.server")
        expectOrder("1234")
    }

    func testDirectionFlipsAndSurvivesTabSwitch() {
        choose("favorites.sort.title")
        expectOrder("1234")
        choose("favorites.sort.direction")
        XCTAssertEqual(app.buttons["favorites.sort.direction"].value as? String, "descending")
        expectOrder("4321")
        // Picking the selected option again flips it back.
        choose("favorites.sort.title")
        expectOrder("1234")
        choose("favorites.sort.direction")
        expectOrder("4321")

        // Leave the tab and come back: the choice is saved for the profile.
        remote.press(.menu)
        let tab = app.tabBars.buttons["Home"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        for _ in 0..<6 where !tab.hasFocus { remote.press(.left); Thread.sleep(forTimeInterval: 0.3) }
        for _ in 0..<6 where !app.tabBars.buttons["Favorites"].hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(app.buttons["favorites.sort.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["favorites.sort.title"].isSelected)
        expectOrder("4321")
    }
}
