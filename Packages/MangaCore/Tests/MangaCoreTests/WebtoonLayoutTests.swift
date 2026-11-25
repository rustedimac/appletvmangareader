import XCTest
@testable import MangaCore

final class WebtoonLayoutTests: XCTestCase {
    let strip = PageSize(width: 800, height: 1280)
    let long = PageSize(width: 720, height: 20000)

    func seg(_ id: String, _ sizes: [PageSize?]) -> WebtoonSegment { WebtoonSegment(id: id, sizes: sizes) }

    // MARK: Geometry

    func testColumnWidthCentersOnWholePixels() {
        for screen in [1920, 3840, 1921] {
            for fraction in [0.3, 0.45, 0.6, 0.77, 1.0] {
                let w = WebtoonGeometry.columnPixels(screenPixels: screen, fraction: fraction)
                XCTAssertEqual((screen - w) % 2, 0, "screen \(screen) fraction \(fraction)")
                XCTAssertLessThanOrEqual(w, screen)
                XCTAssertEqual(Double(w), Double(screen) * fraction, accuracy: 2.0)
            }
        }
        XCTAssertEqual(WebtoonGeometry.columnPixels(screenPixels: 3840, fraction: 2), 3840)
        XCTAssertEqual(WebtoonGeometry.columnPixels(screenPixels: 3840, fraction: 0), 1152)
        XCTAssertEqual(WebtoonGeometry.columnX(screenPixels: 3840, columnPixels: 2304), 768)
    }

    func testPageHeightFromAspect() {
        XCTAssertEqual(WebtoonGeometry.pageHeightPixels(strip, columnPixels: 2304, estimate: 0.7), 3686)
        XCTAssertEqual(WebtoonGeometry.pageHeightPixels(nil, columnPixels: 700, estimate: 0.7), 1000)
        XCTAssertEqual(WebtoonGeometry.pageHeightPixels(PageSize(width: 0, height: 0), columnPixels: 700, estimate: 0.7), 1000)
        XCTAssertEqual(WebtoonGeometry.pageHeightPixels(PageSize(width: 100000, height: 1), columnPixels: 10, estimate: 0.7), 1)
    }

    func testEstimateIsMedianOfKnownPages() {
        XCTAssertEqual(WebtoonGeometry.estimatedAspect(known: []), SpreadGeometry.placeholderAspect)
        let a = PageSize(width: 800, height: 1000)  // 0.8
        let b = PageSize(width: 800, height: 2000)  // 0.4
        let c = PageSize(width: 800, height: 1600)  // 0.5
        XCTAssertEqual(WebtoonGeometry.estimatedAspect(known: [a, b, c]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(WebtoonGeometry.estimatedAspect(known: [a, b]), 0.6, accuracy: 1e-9)
    }

    // MARK: Layout

    func testPagesJoinWithNoGapsOrOverlaps() {
        let sizes: [PageSize?] = [strip, PageSize(width: 799, height: 3333), nil, PageSize(width: 1600, height: 900), strip]
        let layout = WebtoonLayout(segments: [seg("a", sizes), seg("b", sizes)], columnPixels: 2303, breakHeight: 440, endHeight: 520)
        var y = 0
        for item in layout.items {
            XCTAssertEqual(item.y, y, "\(item.kind) starts where the previous item ends")
            XCTAssertGreaterThan(item.height, 0)
            y = item.maxY
        }
        XCTAssertEqual(layout.totalHeight, y)
        XCTAssertEqual(layout.items.filter { if case .chapterBreak = $0.kind { return true }; return false }.count, 1)
        XCTAssertEqual(layout.items.last?.kind, .end)
    }

    func testUnknownPagesUseTheChaptersKnownAspect() {
        let layout = WebtoonLayout(segments: [seg("a", [strip, nil])], columnPixels: 800, breakHeight: 0)
        XCTAssertEqual(layout.items[1].height, 1280)
    }

    func testItemLookup() {
        let layout = WebtoonLayout(segments: [seg("a", [strip, strip]), seg("b", [strip])], columnPixels: 800, breakHeight: 100)
        // a0 0..<1280, a1 1280..<2560, break 2560..<2660, b0 2660..<3940
        XCTAssertEqual(layout.itemIndex(atY: -50), 0)
        XCTAssertEqual(layout.itemIndex(atY: 1279), 0)
        XCTAssertEqual(layout.itemIndex(atY: 1280), 1)
        XCTAssertEqual(layout.items[layout.itemIndex(atY: 2600)!].kind, .chapterBreak(before: "b"))
        XCTAssertEqual(layout.itemIndex(atY: 99999), 3)
        XCTAssertEqual(layout.itemIndices(from: 1000, to: 2700), 0..<4)
        XCTAssertEqual(layout.itemIndices(from: 1280, to: 2560), 1..<2)
        XCTAssertEqual(layout.item(segment: "b", page: 0)?.y, 2660)
        XCTAssertEqual(layout.item(segment: "a", page: 99)?.y, 1280)
        XCTAssertNil(layout.item(segment: "zzz", page: 0))
        XCTAssertEqual(layout.maxOffset(viewport: 1080), 3940 - 1080)
        XCTAssertEqual(layout.maxOffset(viewport: 9999), 0)
    }

    func testReadingPosition() {
        let layout = WebtoonLayout(segments: [seg("a", [strip, strip, strip]), seg("b", [strip, strip])],
                                   columnPixels: 800, breakHeight: 100)
        // a: 0, 1280, 2560 (ends 3840); break 3840..<3940; b: 3940, 5220
        XCTAssertEqual(layout.readingPosition(topY: 0, bottomY: 1080)?.page, 0)
        XCTAssertEqual(layout.readingPosition(topY: 1300, bottomY: 2380)?.page, 1)
        // Last page's bottom on screen counts as reading the last page.
        let end = layout.readingPosition(topY: 2000, bottomY: 3900)
        XCTAssertEqual(end?.segment, "a")
        XCTAssertEqual(end?.page, 2)
        // The divider at the top means the next chapter has started.
        let next = layout.readingPosition(topY: 3850, bottomY: 4930)
        XCTAssertEqual(next?.segment, "b")
        XCTAssertEqual(next?.page, 0)
    }

    func testReadingPositionOnEndFooter() {
        let layout = WebtoonLayout(segments: [seg("a", [strip, strip])], columnPixels: 800, breakHeight: 100, endHeight: 300)
        let p = layout.readingPosition(topY: 2600, bottomY: 3000)
        XCTAssertEqual(p?.segment, "a")
        XCTAssertEqual(p?.page, 1)
    }

    func testTwoHundredPageChapterOnlyTouchesNearbyItems() {
        let sizes = [PageSize?](repeating: strip, count: 240)
        let layout = WebtoonLayout(segments: [seg("a", sizes)], columnPixels: 2304, breakHeight: 0)
        XCTAssertEqual(layout.items.count, 240)
        let top = layout.item(segment: "a", page: 150)!.y
        let range = layout.itemIndices(from: top - 1080, to: top + 2160 + 1080)
        XCTAssertLessThanOrEqual(range.count, 3)
        XCTAssertTrue(range.contains(150))
    }

    // MARK: Anchoring

    func testAnchorKeepsContentStillWhenPagesAboveChangeHeight() {
        // Suwayomi: nothing known, then page 0 and 1 arrive much taller.
        let before = WebtoonLayout(segments: [seg("a", [nil, nil, nil, nil])], columnPixels: 700, breakHeight: 0)
        let offset = before.item(segment: "a", page: 2)!.y + 123
        let anchor = WebtoonAnchor.capture(before, offsetY: offset)!
        XCTAssertEqual(anchor.kind, .page(segment: "a", page: 2))
        let tallSize = PageSize(width: 700, height: 5000)
        let after = WebtoonLayout(segments: [seg("a", [tallSize, tallSize, nil, nil])], columnPixels: 700, breakHeight: 0)
        let resolved = anchor.resolve(in: after)!
        XCTAssertEqual(resolved - after.item(segment: "a", page: 2)!.y, 123 * after.items[2].height / before.items[2].height,
                       "same spot inside the anchored page")
        // The anchored page itself got its estimate from the new known sizes,
        // so keep the position proportional within it.
        XCTAssertEqual(after.items[2].height, 5000)
    }

    func testAnchorSurvivesPrependingAChapter() {
        let a = seg("a", [strip, strip])
        let before = WebtoonLayout(segments: [a], columnPixels: 800, breakHeight: 100)
        let anchor = WebtoonAnchor.capture(before, offsetY: 1300)!
        let after = WebtoonLayout(segments: [seg("z", [strip, strip, strip]), a], columnPixels: 800, breakHeight: 100)
        XCTAssertEqual(anchor.resolve(in: after), 3 * 1280 + 100 + 1300)
    }

    func testAnchorSurvivesDroppingAChapterAbove() {
        let a = seg("a", [strip, strip])
        let b = seg("b", [strip, strip])
        let before = WebtoonLayout(segments: [a, b], columnPixels: 800, breakHeight: 100)
        let offset = before.item(segment: "b", page: 1)!.y + 40
        let anchor = WebtoonAnchor.capture(before, offsetY: offset)!
        let after = WebtoonLayout(segments: [b], columnPixels: 800, breakHeight: 100)
        XCTAssertEqual(anchor.resolve(in: after), 1280 + 40)
    }

    func testAnchorScalesWithColumnWidth() {
        let before = WebtoonLayout(segments: [seg("a", [strip, strip])], columnPixels: 800, breakHeight: 0)
        let anchor = WebtoonAnchor.capture(before, offsetY: 1280 + 640)!
        let after = WebtoonLayout(segments: [seg("a", [strip, strip])], columnPixels: 400, breakHeight: 0)
        XCTAssertEqual(anchor.resolve(in: after), 640 + 320)
    }

    func testAnchorForMissingItemIsNil() {
        let before = WebtoonLayout(segments: [seg("a", [strip])], columnPixels: 800, breakHeight: 0)
        let anchor = WebtoonAnchor.capture(before, offsetY: 10)!
        XCTAssertNil(anchor.resolve(in: WebtoonLayout(segments: [seg("b", [strip])], columnPixels: 800, breakHeight: 0)))
    }

    // MARK: Scrolling

    func testStepTargetsClamp() {
        XCTAssertEqual(WebtoonScrolling.stepTarget(from: 0, forward: true, viewport: 1080, step: 0.75, maxOffset: 5000), 810)
        XCTAssertEqual(WebtoonScrolling.stepTarget(from: 4800, forward: true, viewport: 1080, step: 0.75, maxOffset: 5000), 5000)
        XCTAssertEqual(WebtoonScrolling.stepTarget(from: 300, forward: false, viewport: 1080, step: 0.75, maxOffset: 5000), 0)
        XCTAssertEqual(WebtoonScrolling.stepTarget(from: 0, forward: true, viewport: 1000, step: 5, maxOffset: 5000), 1000)
    }

    func testHoldSpeedRamps() {
        let slow = WebtoonScrolling.holdSpeed(heldFor: 0, viewport: 1000)
        let mid = WebtoonScrolling.holdSpeed(heldFor: 0.75, viewport: 1000)
        let fast = WebtoonScrolling.holdSpeed(heldFor: 10, viewport: 1000)
        XCTAssertLessThan(slow, mid)
        XCTAssertLessThan(mid, fast)
        XCTAssertEqual(fast, WebtoonScrolling.holdSpeed(heldFor: 100, viewport: 1000))
    }

    func testNearEdges() {
        XCTAssertTrue(WebtoonScrolling.nearEnd(offset: 8000, viewport: 1000, totalHeight: 10000))
        XCTAssertFalse(WebtoonScrolling.nearEnd(offset: 1000, viewport: 1000, totalHeight: 10000))
        XCTAssertTrue(WebtoonScrolling.nearStart(offset: 500, viewport: 1000))
        XCTAssertFalse(WebtoonScrolling.nearStart(offset: 1500, viewport: 1000))
    }

    // MARK: Tiles

    func testOrdinaryPageIsOneTileAtColumnWidth() {
        let plan = WebtoonTilePlan(source: PageSize(width: 1600, height: 2560), displayWidth: 800, displayHeight: 1280)
        XCTAssertEqual(plan.tiles.count, 1)
        XCTAssertEqual(plan.decodeWidth, 800)
        XCTAssertEqual(plan.decodeHeight, 1280)
        XCTAssertFalse(plan.requiresExactSize)
        XCTAssertEqual(plan.tiles[0].displayHeight, 1280)
    }

    func testSmallSourceIsNotUpscaledInMemory() {
        let plan = WebtoonTilePlan(source: PageSize(width: 400, height: 600), displayWidth: 2304, displayHeight: 3456)
        XCTAssertEqual(plan.decodeWidth, 400)
        XCTAssertEqual(plan.decodeHeight, 600)
        XCTAssertEqual(plan.tiles, [.init(sourceY: 0, sourceHeight: 600, displayY: 0, displayHeight: 3456)])
    }

    func testVeryTallStripIsTiledSeamlesslyWithinMemoryBudget() {
        let displayWidth = 2304
        let displayHeight = WebtoonGeometry.pageHeightPixels(long, columnPixels: displayWidth, estimate: 0)
        let plan = WebtoonTilePlan(source: long, displayWidth: displayWidth, displayHeight: displayHeight)
        XCTAssertGreaterThan(plan.tiles.count, 1)
        XCTAssertTrue(plan.requiresExactSize)
        XCTAssertLessThanOrEqual(plan.decodeWidth * plan.decodeHeight * 4, 48 << 20)
        var sourceY = 0, displayY = 0
        for tile in plan.tiles {
            XCTAssertEqual(tile.sourceY, sourceY)
            XCTAssertEqual(tile.displayY, displayY)
            XCTAssertLessThanOrEqual(tile.sourceHeight, 4096)
            XCTAssertGreaterThan(tile.displayHeight, 0)
            sourceY += tile.sourceHeight
            displayY += tile.displayHeight
        }
        XCTAssertEqual(sourceY, plan.decodeHeight)
        XCTAssertEqual(displayY, displayHeight, "tiles cover the page exactly")
    }

    func testTallStripAtSourceResolutionWhenItFits() {
        // 720×20000 shown at 720 wide: decode 1:1 in 5 tiles, each row one pixel.
        let plan = WebtoonTilePlan(source: long, displayWidth: 720, displayHeight: 20000, maxBytes: 64 << 20)
        XCTAssertEqual(plan.decodeWidth, 720)
        XCTAssertEqual(plan.decodeHeight, 20000)
        XCTAssertEqual(plan.tiles.count, 5)
        XCTAssertTrue(plan.tiles.allSatisfy { $0.sourceHeight == $0.displayHeight })
    }

    // MARK: Strip

    func chapter(_ n: Int) -> Chapter {
        Chapter(id: "c\(n)", seriesRef: SeriesRef(serverID: UUID(), seriesID: "s"), title: "Chapter \(n)",
                number: Double(n), pageCount: 2)
    }

    func segment(_ n: Int, sizes: [Int: PageSize] = [:]) -> WebtoonStrip.Segment {
        let pages = (0..<2).map { PageDescriptor(index: $0, url: URL(string: "https://x/\(n)/\($0)")!) }
        return WebtoonStrip.Segment(chapter: chapter(n), pages: pages.reversed(), sizes: sizes)
    }

    func testStripAppendPrependTrim() {
        var s = WebtoonStrip()
        s.reset(segment(2))
        s.append(segment(3))
        s.append(segment(3))
        s.prepend(segment(1))
        XCTAssertEqual(s.segments.map(\.id), ["c1", "c2", "c3"])
        s.append(segment(4))
        XCTAssertEqual(s.trim(around: "c3"), ["c1"])
        XCTAssertEqual(s.segments.map(\.id), ["c2", "c3", "c4"])
        XCTAssertEqual(s.trim(around: "nope"), [])
    }

    func testSegmentOrdersPagesAndMergesSizes() {
        let size = PageSize(width: 1, height: 2)
        var s = WebtoonStrip(segments: [segment(1, sizes: [1: size])])
        XCTAssertEqual(s.first?.pages.map(\.index), [0, 1])
        XCTAssertEqual(s.first?.sizes, [nil, size])
        XCTAssertTrue(s.setSize(size, segment: "c1", page: 0))
        XCTAssertFalse(s.setSize(size, segment: "c1", page: 0))
        XCTAssertFalse(s.setSize(size, segment: "c1", page: 5))
        XCTAssertEqual(s.first?.knownSizes, [0: size, 1: size])
    }

    func testNeighbors() {
        let chapters = [chapter(1), chapter(2), chapter(3)]
        XCTAssertEqual(WebtoonStrip.neighbor(of: "c2", in: chapters, offset: 1)?.id, "c3")
        XCTAssertEqual(WebtoonStrip.neighbor(of: "c2", in: chapters, offset: -1)?.id, "c1")
        XCTAssertNil(WebtoonStrip.neighbor(of: "c3", in: chapters, offset: 1))
        XCTAssertNil(WebtoonStrip.neighbor(of: "x", in: chapters, offset: 1))
    }
}
