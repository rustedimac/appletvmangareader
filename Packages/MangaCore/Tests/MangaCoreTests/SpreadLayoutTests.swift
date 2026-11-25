import XCTest
@testable import MangaCore

final class SpreadLayoutTests: XCTestCase {
    let tall = PageSize(width: 800, height: 1200)
    let wide = PageSize(width: 1600, height: 1200)

    func layout(_ sizes: [PageSize?], alone: Bool = true, shift: Bool = false) -> [Spread] {
        SpreadLayout(sizes: sizes, firstPageAlone: alone, shift: shift).spreads
    }

    func testEmptyChapter() {
        XCTAssertEqual(layout([]), [])
    }

    func testSinglePage() {
        XCTAssertEqual(layout([tall]), [.single(0)])
        XCTAssertEqual(layout([tall], alone: false), [.single(0)])
    }

    func testCoverAloneThenPairs() {
        let s = layout(Array(repeating: tall, count: 6))
        XCTAssertEqual(s, [.single(0), .double(1, 2), .double(3, 4), .single(5)])
    }

    func testNoCoverPairsFromStart() {
        let s = layout(Array(repeating: tall, count: 6), alone: false)
        XCTAssertEqual(s, [.double(0, 1), .double(2, 3), .double(4, 5)])
    }

    func testShiftFlipsParity() {
        let pages = Array(repeating: tall, count: 6)
        XCTAssertEqual(layout(pages, alone: true, shift: true), layout(pages, alone: false))
        XCTAssertEqual(layout(pages, alone: false, shift: true), layout(pages, alone: true))
    }

    func testWidePageStandsAloneAndResetsPairing() {
        // cover, 1-2, [3 wide], 4-5, 6
        let s = layout([tall, tall, tall, wide, tall, tall, tall])
        XCTAssertEqual(s, [.single(0), .double(1, 2), .single(3), .double(4, 5), .single(6)])
    }

    func testPageBeforeWidePageIsAlone() {
        // cover, 1-2, 3 (alone, next is wide), [4 wide], 5-6
        let s = layout([tall, tall, tall, tall, wide, tall, tall])
        XCTAssertEqual(s, [.single(0), .double(1, 2), .single(3), .single(4), .double(5, 6)])
    }

    func testWideFirstPageIsNotTreatedAsCover() {
        // A wide opener is alone anyway, and pairing after it starts fresh,
        // so the cover rule must not also isolate page 1.
        let s = layout([wide, tall, tall, tall])
        XCTAssertEqual(s, [.single(0), .double(1, 2), .single(3)])
    }

    func testUnknownSizesTreatedAsTall() {
        let s = layout([nil, nil, nil])
        XCTAssertEqual(s, [.single(0), .double(1, 2)])
    }

    func testEveryPageAppearsExactlyOnceInOrder() {
        // Exhaustive over all wide/tall patterns of length 1...10.
        for n in 1...10 {
            for mask in 0..<(1 << n) {
                for alone in [true, false] {
                    for shift in [true, false] {
                        let sizes: [PageSize?] = (0..<n).map { (mask >> $0) & 1 == 1 ? wide : tall }
                        let spreads = layout(sizes, alone: alone, shift: shift)
                        XCTAssertEqual(spreads.flatMap(\.pages), Array(0..<n))
                        for spread in spreads {
                            if case .double(let a, let b) = spread {
                                XCTAssertFalse(sizes[a]!.isWide)
                                XCTAssertFalse(sizes[b]!.isWide)
                                XCTAssertEqual(b, a + 1)
                            }
                        }
                    }
                }
            }
        }
    }

    func testSpreadIndexContainingPage() {
        let l = SpreadLayout(sizes: Array(repeating: tall, count: 5), firstPageAlone: true, shift: false)
        XCTAssertEqual(l.spreadIndex(containing: 0), 0)
        XCTAssertEqual(l.spreadIndex(containing: 1), 1)
        XCTAssertEqual(l.spreadIndex(containing: 2), 1)
        XCTAssertEqual(l.spreadIndex(containing: 4), 2)
        XCTAssertEqual(l.spreadIndex(containing: 99), 2)
        XCTAssertEqual(l.spreadIndex(containing: -1), 0)
    }

    func testScreenOrderRightToLeft() {
        XCTAssertEqual(Spread.double(1, 2).screenOrder(.rightToLeft), [2, 1])
        XCTAssertEqual(Spread.double(1, 2).screenOrder(.leftToRight), [1, 2])
        XCTAssertEqual(Spread.single(3).screenOrder(.rightToLeft), [3])
    }

    func testReaderSettingsLayout() {
        var settings = ReaderSettings()
        settings.layout = .single
        XCTAssertEqual(settings.layout(for: [tall, tall, tall]).spreads, [.single(0), .single(1), .single(2)])
        settings.layout = .double
        XCTAssertEqual(settings.layout(for: [tall, tall, tall]).spreads, [.single(0), .double(1, 2)])
        settings.mode = .webtoon
        XCTAssertEqual(settings.layout(for: [tall, tall]).count, 2)
    }

    func testIsWide() {
        XCTAssertTrue(wide.isWide)
        XCTAssertFalse(tall.isWide)
        XCTAssertFalse(PageSize(width: 100, height: 100).isWide)
        XCTAssertFalse(PageSize(width: 100, height: 0).isWide)
    }
}
