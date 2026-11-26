import XCTest
@testable import MangaCore

final class PagePairingTests: XCTestCase {
    private let tall = Optional(PageSize(width: 400, height: 600))
    private let wide = Optional(PageSize(width: 1200, height: 600))

    /// The reason the two controls were merged: for every chapter shape,
    /// shifting is the same as flipping First Page Alone.
    func testShiftIsTheSameAsFlippingFirstPageAlone() {
        let shapes: [[PageSize?]] = [
            Array(repeating: tall, count: 7),
            Array(repeating: tall, count: 8),
            [wide, tall, tall, tall, tall],
            [tall, tall, tall, wide, tall, tall, tall],
            [tall, wide, tall, tall],
            [tall],
            [],
        ]
        for sizes in shapes {
            for alone in [true, false] {
                let shifted = SpreadLayout(sizes: sizes, firstPageAlone: alone, shift: true)
                let flipped = SpreadLayout(sizes: sizes, firstPageAlone: !alone, shift: false)
                XCTAssertEqual(shifted, flipped, "\(sizes.count) pages, alone \(alone)")
            }
        }
    }

    func testShowsFirstPageAloneCountsOldShift() {
        XCTAssertTrue(ReaderSettings(firstPageAlone: true, shiftPairing: false).showsFirstPageAlone)
        XCTAssertFalse(ReaderSettings(firstPageAlone: true, shiftPairing: true).showsFirstPageAlone)
        XCTAssertTrue(ReaderSettings(firstPageAlone: false, shiftPairing: true).showsFirstPageAlone)
        XCTAssertFalse(ReaderSettings(firstPageAlone: false, shiftPairing: false).showsFirstPageAlone)
    }

    func testNormalizingKeepsTheLayout() {
        let sizes = Array(repeating: tall, count: 6)
        for alone in [true, false] {
            for shift in [true, false] {
                let old = ReaderSettings(firstPageAlone: alone, shiftPairing: shift)
                let new = old.normalizedPairing
                XCTAssertFalse(new.shiftPairing)
                XCTAssertEqual(new.firstPageAlone, old.showsFirstPageAlone)
                XCTAssertEqual(new.layout(for: sizes), old.layout(for: sizes))
            }
        }
    }

    func testSettingFirstPageAloneClearsShift() {
        let shifted = ReaderSettings(firstPageAlone: true, shiftPairing: true) // shows Off
        let on = shifted.withFirstPageAlone(true)
        XCTAssertTrue(on.showsFirstPageAlone)
        XCTAssertFalse(on.shiftPairing)
        XCTAssertEqual(on.layout(for: Array(repeating: tall, count: 5)).spreads.first, .single(0))
    }

    func testStateFoldsShiftOnReadAndWrite() {
        let profile = UUID()
        let ref = SeriesRef(serverID: UUID(), seriesID: "1")
        var state = AppState()
        state.setReaderSettings(ReaderSettings(firstPageAlone: false, shiftPairing: true), for: ref, profile: profile)
        let read = state.readerSettings(for: ref, profile: profile)
        XCTAssertTrue(read.firstPageAlone)
        XCTAssertFalse(read.shiftPairing)

        state.setDefaultReaderSettings(ReaderSettings(firstPageAlone: true, shiftPairing: true), profile: profile)
        XCTAssertEqual(state.profileData[profile.uuidString]?.defaultReaderSettings.firstPageAlone, false)
        XCTAssertEqual(state.profileData[profile.uuidString]?.defaultReaderSettings.shiftPairing, false)
    }
}
