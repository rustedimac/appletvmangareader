import XCTest
@testable import MangaCore

final class ReaderControlsTests: XCTestCase {
    func testEveryReaderHasAMenuRouteBesidesPlayPause() {
        for mode in ReadingMode.allCases {
            let entries = ReaderControls.remote(for: mode)
            let hold = entries.first { $0.input.contains("hold Select") || $0.input == "Hold Select" }
            XCTAssertNotNil(hold, "\(mode) needs a hold-Select route to the options")
            XCTAssertTrue(hold?.action.hasPrefix("Reader options") == true)
            XCTAssertTrue(entries.contains { $0.input.hasPrefix("Menu") })
        }
        XCTAssertTrue(ReaderControls.bookRemote.contains { $0.input.hasPrefix("Click or hold Select") })
    }

    func testPlayPauseAutoScrollsOnlyInVerticalMode() {
        let paged = ReaderControls.remote(for: .paged).first { $0.input == "Play/Pause" }
        let webtoon = ReaderControls.remote(for: .webtoon).first { $0.input == "Play/Pause" }
        XCTAssertEqual(paged?.action, "Reader options")
        XCTAssertEqual(webtoon?.action, "Start or stop auto-scroll")
    }

    func testGamepadGuideMatchesTheMapping() {
        XCTAssertEqual(GamepadMapping.action(for: .buttonY, mode: .webtoon), .toggleMenu)
        XCTAssertTrue(ReaderControls.gamepad.contains { $0.input.hasPrefix("Y") && $0.action == "Reader options" })
        XCTAssertEqual(GamepadMapping.action(for: .buttonX, mode: .webtoon), .toggleAutoScroll)
        XCTAssertTrue(ReaderControls.gamepad.contains { $0.input == "X" && $0.action.contains("auto-scroll") })
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
