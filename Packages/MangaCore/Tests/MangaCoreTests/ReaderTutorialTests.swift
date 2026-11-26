import XCTest
@testable import MangaCore

final class ReaderTutorialTests: XCTestCase {
    func testEveryStepTeachesAnInputTheReaderUses() {
        for mode in ReadingMode.allCases {
            let inputs = Set(ReaderControls.remote(for: mode).map(\.input))
            for step in ReaderTutorial.steps(for: mode) {
                XCTAssertTrue(inputs.contains(step.input), "\(mode): \(step.input) isn't in ReaderControls")
            }
        }
    }

    func testOptionsStepUsesTheHoldRouteAndTheTutorialEndsOnFinish() {
        for mode in ReadingMode.allCases {
            let steps = ReaderTutorial.steps(for: mode)
            XCTAssertEqual(steps.first { $0.goal == .openOptions }?.input, "Hold Play/Pause")
            XCTAssertEqual(steps.last?.goal, .finish)
            XCTAssertEqual(steps.filter { $0.goal == .finish }.count, 1)
            XCTAssertEqual(steps.map(\.id), Array(steps.indices))
            XCTAssertTrue(steps.contains { $0.goal == .showPageNumber })
        }
    }

    func testPagedTeachesZoomBookmarkAndTimer() {
        let goals = ReaderTutorial.steps(for: .paged).map(\.goal)
        for goal in [ReaderTutorial.Goal.turnPage, .zoomIn, .zoomOut, .bookmark, .startPlay, .stopPlay] {
            XCTAssertTrue(goals.contains(goal), "\(goal)")
        }
        XCTAssertLessThan(goals.firstIndex(of: .zoomIn)!, goals.firstIndex(of: .zoomOut)!)
        XCTAssertLessThan(goals.firstIndex(of: .startPlay)!, goals.firstIndex(of: .stopPlay)!)
    }

    func testVerticalTeachesScrollAndSpeed() {
        let goals = ReaderTutorial.steps(for: .webtoon).map(\.goal)
        XCTAssertEqual(goals.first, .scroll)
        let start = goals.firstIndex(of: .startPlay)!
        XCTAssertEqual(goals[start + 1], .changeSpeed, "speed is changed while it scrolls")
        XCTAssertEqual(goals[start + 2], .stopPlay)
        XCTAssertFalse(goals.contains(.zoomIn))
    }

    func testProgressMovesOnlyOnTheAskedGoal() {
        var progress = ReaderTutorial.Progress(mode: .paged)
        XCTAssertEqual(progress.current?.goal, .turnPage)
        XCTAssertFalse(progress.record(.openOptions), "other inputs are ignored")
        XCTAssertEqual(progress.index, 0)
        XCTAssertTrue(progress.record(.turnPage))
        XCTAssertEqual(progress.current?.goal, .showPageNumber)
        for step in progress.steps.dropFirst() where step.goal != .finish {
            XCTAssertTrue(progress.record(step.goal))
        }
        XCTAssertTrue(progress.isFinished)
        XCTAssertFalse(progress.record(.finish), "the last step waits for Menu")
        XCTAssertTrue(progress.isFinished)
    }

    func testSampleCreditNamesAuthorAndLicense() {
        XCTAssertTrue(ReaderTutorial.sampleCredit.contains("David Revoy"))
        XCTAssertTrue(ReaderTutorial.sampleCredit.contains("CC BY 4.0"))
        XCTAssertTrue(ReaderTutorial.sampleCredit.contains("peppercarrot.com"))
        XCTAssertEqual(ReaderTutorial.samplePageNames.count, 3)
    }
}
