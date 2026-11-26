import XCTest
@testable import MangaCore

final class ReaderMenuOptionsTests: XCTestCase {
    func testPagedDoubleShowsPairingRows() {
        let s = ReaderSettings(mode: .paged, layout: .double)
        XCTAssertEqual(ReaderMenuOptions.items(for: s),
                       [.mode, .layout, .direction, .firstPageAlone, .shiftPairing,
                        .fit, .cropBorders, .zoom, .background])
    }

    func testPagedSingleHidesPairingRows() {
        let s = ReaderSettings(mode: .paged, layout: .single)
        XCTAssertEqual(ReaderMenuOptions.items(for: s),
                       [.mode, .layout, .direction, .fit, .cropBorders, .zoom, .splitWidePages, .background])
    }

    func testWebtoonShowsWidthAndHidesPagedRows() {
        let s = ReaderSettings(mode: .webtoon, layout: .double)
        XCTAssertEqual(ReaderMenuOptions.items(for: s), [.mode, .webtoonWidth, .autoScroll, .background])
    }

    func testZoomLabel() {
        XCTAssertEqual(ReaderMenuOptions.zoomLabel(2), "2×")
        XCTAssertEqual(ReaderMenuOptions.zoomLabel(1.5), "1.5×")
        XCTAssertEqual(ReaderMenuOptions.zoomLabel(3.0), "3×")
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

final class ReaderSettingsCodingTests: XCTestCase {
    func testSettingsFromAnOlderBuildStillDecode() throws {
        // Saved before crop/fit/zoom existed.
        let json = #"{"mode":"paged","direction":"leftToRight","layout":"single","firstPageAlone":false,"shiftPairing":true,"background":"gray","webtoonWidth":0.8,"webtoonScrollStep":0.5}"#
        let s = try JSONDecoder().decode(ReaderSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.direction, .leftToRight)
        XCTAssertEqual(s.layout, .single)
        XCTAssertTrue(s.shiftPairing)
        XCTAssertEqual(s.webtoonWidth, 0.8)
        XCTAssertFalse(s.cropBorders)
        XCTAssertEqual(s.fit, .screen)
        XCTAssertEqual(s.zoomScale, 2)
    }

    func testUnknownValuesFallBackToDefaults() throws {
        let json = #"{"mode":"carousel","fit":"stretch","cropBorders":true}"#
        let s = try JSONDecoder().decode(ReaderSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.mode, .paged)
        XCTAssertEqual(s.fit, .screen)
        XCTAssertTrue(s.cropBorders)
    }

    func testRoundTrip() throws {
        let s = ReaderSettings(cropBorders: true, fit: .width, zoomScale: 3)
        let back = try JSONDecoder().decode(ReaderSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testZoomIsClamped() {
        XCTAssertEqual(ReaderSettings(zoomScale: 10).clampedZoomScale, 4)
        XCTAssertEqual(ReaderSettings(zoomScale: 0.5).clampedZoomScale, 1.25)
    }
}
