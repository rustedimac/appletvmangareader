import XCTest
@testable import MangaCore

final class ReaderControlsTests: XCTestCase {
    func testHoldingPlayPauseOpensTheOptionsInEveryReader() {
        for mode in ReadingMode.allCases {
            let entries = ReaderControls.remote(for: mode)
            XCTAssertEqual(entries.first { $0.input == "Hold Play/Pause" }?.action, "Reader options", "\(mode)")
            XCTAssertTrue(entries.contains { $0.input.hasPrefix("Menu") })
        }
        XCTAssertEqual(ReaderControls.bookRemote.first { $0.input == "Hold Play/Pause" }?.action, "Reader options")
    }

    func testOnlyOneInputOpensTheOptions() {
        for entries in ReadingMode.allCases.map(ReaderControls.remote(for:)) + [ReaderControls.bookRemote] {
            XCTAssertEqual(entries.filter { $0.action == "Reader options" }.count, 1,
                           "no second route to the options: \(entries)")
        }
    }

    func testPlayPausePlaysInBothImageReaders() {
        let paged = ReaderControls.remote(for: .paged).first { $0.input == "Play/Pause" }
        let webtoon = ReaderControls.remote(for: .webtoon).first { $0.input == "Play/Pause" }
        XCTAssertTrue(paged?.action.contains("timer") == true)
        XCTAssertEqual(webtoon?.action, "Start or stop auto-scroll")
    }

    func testGamepadGuideMatchesTheMapping() {
        XCTAssertEqual(GamepadMapping.action(for: .menu, mode: .webtoon), .toggleMenu)
        XCTAssertTrue(ReaderControls.gamepad.contains { $0.input.hasPrefix("☰") && $0.action == "Reader options" })
        XCTAssertEqual(GamepadMapping.action(for: .buttonY, mode: .paged), .toggleBookmark)
        XCTAssertTrue(ReaderControls.gamepad.contains { $0.input == "Y" && $0.action.contains("Bookmark") })
        XCTAssertEqual(GamepadMapping.action(for: .buttonX, mode: .webtoon), .togglePlay)
        XCTAssertTrue(ReaderControls.gamepad.contains { $0.input == "X" && $0.action.contains("Auto-scroll") })
        XCTAssertEqual(GamepadMapping.action(for: .rightShoulder, mode: .paged), .jumpChapter(forward: true))
        XCTAssertTrue(ReaderControls.gamepad.contains { $0.input.hasPrefix("L1 / R1") && $0.action.contains("chapter") })
        XCTAssertFalse(ReaderControls.gamepad.contains { $0.input.contains("L2") }, "nothing needs triggers")
    }

    func testHintsNameTheHoldRoute() {
        for mode in ReadingMode.allCases {
            XCTAssertTrue(ReaderControls.hint(for: mode).hasPrefix("Hold Play/Pause for reader options"))
        }
        XCTAssertEqual(ReaderControls.hudHint, "Hold for options")
    }

    func testHintShowsAFewTimesThenStops() {
        let defaults = UserDefaults(suiteName: "ReaderControlsTests.\(UUID().uuidString)")!
        let tracker = ReaderHintTracker(defaults: defaults)
        for _ in 0..<ReaderControls.hintShowCount {
            XCTAssertTrue(tracker.takeHint(for: .webtoon))
        }
        XCTAssertFalse(tracker.takeHint(for: .webtoon))
        XCTAssertTrue(tracker.takeHint(for: .paged), "modes are counted separately")
    }

    func testOpeningTheMenuRetiresTheHint() {
        let defaults = UserDefaults(suiteName: "ReaderControlsTests.\(UUID().uuidString)")!
        let tracker = ReaderHintTracker(defaults: defaults)
        XCTAssertTrue(tracker.takeHint(for: .paged))
        tracker.menuOpened(in: .paged)
        XCTAssertFalse(tracker.takeHint(for: .paged))
        tracker.reset()
        XCTAssertTrue(tracker.takeHint(for: .paged))
    }
}
