import XCTest
@testable import MangaCore

final class ReaderMenuOptionsTests: XCTestCase {
    func testPagedDoubleShowsPairingRows() {
        let s = ReaderSettings(mode: .paged, layout: .double)
        XCTAssertEqual(ReaderMenuOptions.items(for: s),
                       [.mode, .layout, .direction, .firstPageAlone, .shiftPairing, .background])
    }

    func testPagedSingleHidesPairingRows() {
        let s = ReaderSettings(mode: .paged, layout: .single)
        XCTAssertEqual(ReaderMenuOptions.items(for: s), [.mode, .layout, .direction, .background])
    }

    func testWebtoonShowsWidthAndHidesPagedRows() {
        let s = ReaderSettings(mode: .webtoon, layout: .double)
        XCTAssertEqual(ReaderMenuOptions.items(for: s), [.mode, .webtoonWidth, .background])
    }

    func testEveryItemHasATitle() {
        for item in ReaderMenuItem.allCases { XCTAssertFalse(item.title.isEmpty) }
    }

    func testWidthSteppingSnapsAndClamps() {
        XCTAssertEqual(ReaderMenuOptions.steppedWidth(0.6, by: 1), 0.7, accuracy: 1e-9)
        XCTAssertEqual(ReaderMenuOptions.steppedWidth(0.6, by: -1), 0.5, accuracy: 1e-9)
        // Off-grid values snap to the nearest step first.
        XCTAssertEqual(ReaderMenuOptions.steppedWidth(0.62, by: 1), 0.7, accuracy: 1e-9)
        XCTAssertEqual(ReaderMenuOptions.steppedWidth(1.0, by: 1), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ReaderMenuOptions.steppedWidth(0.3, by: -1), 0.3, accuracy: 1e-9)
        XCTAssertEqual(ReaderMenuOptions.steppedWidth(5, by: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ReaderMenuOptions.steppedWidth(-1, by: 0), 0.3, accuracy: 1e-9)
    }

    func testCanStepWidthAtEnds() {
        XCTAssertTrue(ReaderMenuOptions.canStepWidth(0.6, by: 1))
        XCTAssertFalse(ReaderMenuOptions.canStepWidth(1.0, by: 1))
        XCTAssertTrue(ReaderMenuOptions.canStepWidth(1.0, by: -1))
        XCTAssertFalse(ReaderMenuOptions.canStepWidth(0.3, by: -1))
    }

    func testWidthLabel() {
        XCTAssertEqual(ReaderMenuOptions.widthLabel(0.6), "60%")
        XCTAssertEqual(ReaderMenuOptions.widthLabel(1.0), "100%")
        XCTAssertEqual(ReaderMenuOptions.widthLabel(0.33), "30%")
    }

    func testPositionLabel() {
        XCTAssertEqual(ReaderMenuOptions.positionLabel(visiblePages: [0], pageCount: 6), "Page 1 of 6")
        XCTAssertEqual(ReaderMenuOptions.positionLabel(visiblePages: [1, 2], pageCount: 6), "Pages 2–3 of 6")
        XCTAssertEqual(ReaderMenuOptions.positionLabel(visiblePages: [], pageCount: 6), "")
        XCTAssertEqual(ReaderMenuOptions.positionLabel(visiblePages: [0], pageCount: 0), "")
    }

    func testWithChangesOneField() {
        let s = ReaderSettings.default
        let changed = s.with(\.shiftPairing, true)
        XCTAssertTrue(changed.shiftPairing)
        XCTAssertEqual(changed.with(\.shiftPairing, false), s)
    }

    func testShiftChangesPairingThroughSettings() {
        let sizes = Array(repeating: Optional(PageSize(width: 400, height: 600)), count: 5)
        let normal = ReaderSettings.default
        XCTAssertEqual(normal.layout(for: sizes).spreads.first, .single(0))
        XCTAssertEqual(normal.with(\.shiftPairing, true).layout(for: sizes).spreads.first, .double(0, 1))
    }
}
