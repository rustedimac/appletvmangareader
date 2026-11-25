import XCTest
@testable import MangaCore

final class GamepadMappingTests: XCTestCase {
    func testShouldersTurnPagesTowardTheirSideOfTheScreen() {
        for mode in ReadingMode.allCases {
            XCTAssertEqual(GamepadMapping.action(for: .leftShoulder, mode: mode), .turnPage(.left))
            XCTAssertEqual(GamepadMapping.action(for: .rightShoulder, mode: mode), .turnPage(.right))
        }
    }

    func testTriggersJumpChapters() {
        for mode in ReadingMode.allCases {
            XCTAssertEqual(GamepadMapping.action(for: .leftTrigger, mode: mode), .jumpChapter(forward: false))
            XCTAssertEqual(GamepadMapping.action(for: .rightTrigger, mode: mode), .jumpChapter(forward: true))
        }
    }

    func testXTogglesAutoScrollOnlyInVerticalMode() {
        XCTAssertEqual(GamepadMapping.action(for: .buttonX, mode: .webtoon), .toggleAutoScroll)
        XCTAssertNil(GamepadMapping.action(for: .buttonX, mode: .paged))
    }

    func testYAndOptionsToggleTheMenu() {
        XCTAssertEqual(GamepadMapping.action(for: .buttonY, mode: .paged), .toggleMenu)
        XCTAssertEqual(GamepadMapping.action(for: .options, mode: .webtoon), .toggleMenu)
    }

    func testOnlyTheMenuToggleWorksWhileTheMenuIsOpen() {
        for button in GamepadButton.allCases {
            let action = GamepadMapping.action(for: button, mode: .webtoon, menuOpen: true)
            if button == .buttonY || button == .options {
                XCTAssertEqual(action, .toggleMenu)
            } else {
                XCTAssertNil(action, "\(button) should do nothing while the menu is open")
            }
        }
    }
}

final class GamepadStickTests: XCTestCase {
    func testDeadZoneIgnoresDrift() {
        XCTAssertEqual(GamepadStick.scrollSpeed(y: 0, viewport: 1000), 0)
        XCTAssertEqual(GamepadStick.scrollSpeed(y: 0.1, viewport: 1000), 0)
        XCTAssertEqual(GamepadStick.scrollSpeed(y: -0.15, viewport: 1000), 0)
        XCTAssertFalse(GamepadStick.isDeflected(x: 0.1, y: -0.1))
        XCTAssertTrue(GamepadStick.isDeflected(x: 0, y: -0.5))
    }

    func testStickDownScrollsForwardAndUpScrollsBack() {
        XCTAssertGreaterThan(GamepadStick.scrollSpeed(y: -0.8, viewport: 1000), 0)
        XCTAssertLessThan(GamepadStick.scrollSpeed(y: 0.8, viewport: 1000), 0)
    }

    func testFullDeflectionIsTheTopSpeedAndTheCurveIsMonotonic() {
        XCTAssertEqual(GamepadStick.scrollSpeed(y: -1, viewport: 1000), 2500, accuracy: 0.001)
        XCTAssertEqual(GamepadStick.scrollSpeed(y: -1.3, viewport: 1000), 2500, accuracy: 0.001, "clamped")
        var last = 0.0
        for step in 16...100 {
            let speed = GamepadStick.scrollSpeed(y: -Double(step) / 100, viewport: 1000)
            XCTAssertGreaterThan(speed, last)
            last = speed
        }
        // Half a push is well under half speed, so small pushes stay readable.
        XCTAssertLessThan(GamepadStick.scrollSpeed(y: -0.5, viewport: 1000), 2500 * 0.25)
    }
}

final class WebtoonAutoScrollTests: XCTestCase {
    func testLevelsAreOrderedSlowToFast() {
        let speeds = WebtoonAutoScroll.levels.map { WebtoonAutoScroll.speed(level: $0, viewport: 1000) }
        XCTAssertEqual(speeds, speeds.sorted())
        XCTAssertEqual(Set(speeds).count, speeds.count)
        XCTAssertEqual(WebtoonAutoScroll.levels, 1...10)
        XCTAssertTrue(WebtoonAutoScroll.levels.contains(WebtoonAutoScroll.defaultLevel))
    }

    func testSpeedScalesWithTheScreen() {
        let small = WebtoonAutoScroll.speed(level: 4, viewport: 540)
        let big = WebtoonAutoScroll.speed(level: 4, viewport: 1080)
        XCTAssertEqual(big, small * 2, accuracy: 0.0001)
    }

    func testSteppingIsClamped() {
        XCTAssertEqual(WebtoonAutoScroll.stepped(3, by: 1), 4)
        XCTAssertEqual(WebtoonAutoScroll.stepped(10, by: 1), 10)
        XCTAssertEqual(WebtoonAutoScroll.stepped(1, by: -1), 1)
        XCTAssertEqual(WebtoonAutoScroll.stepped(50, by: -1), 9, "out-of-range levels are clamped first")
        XCTAssertFalse(WebtoonAutoScroll.canStep(10, by: 1))
        XCTAssertTrue(WebtoonAutoScroll.canStep(10, by: -1))
        XCTAssertFalse(WebtoonAutoScroll.canStep(1, by: -1))
        XCTAssertEqual(WebtoonAutoScroll.label(3), "Speed 3 of 10")
        XCTAssertEqual(WebtoonAutoScroll.label(0), "Speed 1 of 10")
    }

    func testSwipeUpSpeedsUpAndSwipeDownSlowsDown() {
        XCTAssertEqual(WebtoonAutoScroll.levelChange(forSwipe: 10), 0, "a tap-sized swipe does nothing")
        XCTAssertEqual(WebtoonAutoScroll.levelChange(forSwipe: -60), 1)
        XCTAssertEqual(WebtoonAutoScroll.levelChange(forSwipe: 60), -1)
        XCTAssertEqual(WebtoonAutoScroll.levelChange(forSwipe: -500), 2)
        XCTAssertEqual(WebtoonAutoScroll.levelChange(forSwipe: 760), -3)
    }

    func testAdvanceMovesByTheLevelSpeed() {
        let viewport = 1000.0
        let y = WebtoonAutoScroll.advance(offset: 100, dt: 2, level: 5, viewport: viewport,
                                          maxOffset: 10_000, atEnd: true)
        XCTAssertEqual(y ?? -1, 100 + 2 * WebtoonAutoScroll.speed(level: 5, viewport: viewport), accuracy: 0.0001)
    }

    func testAdvanceClampsThenStopsAtTheEndOfTheSeries() {
        let near = WebtoonAutoScroll.advance(offset: 990, dt: 10, level: 10, viewport: 1000,
                                             maxOffset: 1000, atEnd: true)
        XCTAssertEqual(near, 1000)
        XCTAssertNil(WebtoonAutoScroll.advance(offset: 1000, dt: 0.1, level: 3, viewport: 1000,
                                               maxOffset: 1000, atEnd: true))
    }

    func testAdvanceWaitsAtTheBottomWhileTheNextChapterLoads() {
        XCTAssertEqual(WebtoonAutoScroll.advance(offset: 1000, dt: 0.1, level: 3, viewport: 1000,
                                                 maxOffset: 1000, atEnd: false), 1000)
    }

    func testLevelIsSavedPerProfile() {
        var s = AppState.initial()
        let me = s.profiles[0].id
        let kid = s.addProfile(name: "Kid").id
        XCTAssertEqual(s.autoScrollLevel(profile: me), WebtoonAutoScroll.defaultLevel)
        s.setAutoScrollLevel(7, profile: me)
        XCTAssertEqual(s.autoScrollLevel(profile: me), 7)
        XCTAssertEqual(s.autoScrollLevel(profile: kid), WebtoonAutoScroll.defaultLevel)
        s.setAutoScrollLevel(99, profile: kid)
        XCTAssertEqual(s.autoScrollLevel(profile: kid), 10)
    }

    func testLevelSurvivesEncodingAndOldStateStillDecodes() throws {
        var s = AppState.initial()
        let me = s.profiles[0].id
        s.setAutoScrollLevel(6, profile: me)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(decoded.autoScrollLevel(profile: me), 6)

        // State saved before auto-scroll existed has no such key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var profiles = try XCTUnwrap(json["profileData"] as? [String: [String: Any]])
        profiles[me.uuidString]?.removeValue(forKey: "webtoonAutoScrollLevel")
        json["profileData"] = profiles
        let old = try JSONSerialization.data(withJSONObject: json)
        let migrated = try JSONDecoder().decode(AppState.self, from: old)
        XCTAssertEqual(migrated.autoScrollLevel(profile: me), WebtoonAutoScroll.defaultLevel)
    }
}
