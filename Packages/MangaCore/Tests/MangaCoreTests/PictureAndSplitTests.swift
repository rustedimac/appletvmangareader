import XCTest
@testable import MangaCore

/// Picture controls, split wide pages and the page scrubber (backlog items
/// 6, 7 and 8).
final class PictureAndSplitTests: XCTestCase {
    let tall = PageSize(width: 800, height: 1200)
    let wide = PageSize(width: 1600, height: 1200)

    // MARK: Split wide pages

    func testRightToLeftShowsRightHalfFirst() {
        let s = ReaderSettings(direction: .rightToLeft, layout: .single, splitWidePages: true)
        XCTAssertEqual(s.layout(for: [tall, wide, tall]).spreads,
                       [.single(0), .half(1, .right), .half(1, .left), .single(2)])
    }

    func testLeftToRightShowsLeftHalfFirst() {
        let s = ReaderSettings(direction: .leftToRight, layout: .single, splitWidePages: true)
        XCTAssertEqual(s.layout(for: [wide, tall]).spreads, [.half(0, .left), .half(0, .right), .single(1)])
    }

    func testSplitOffOrDoubleLayoutKeepsWidePagesWhole() {
        let off = ReaderSettings(layout: .single, splitWidePages: false)
        XCTAssertEqual(off.layout(for: [tall, wide]).spreads, [.single(0), .single(1)])
        // Two-page layout already shows a wide page alone; splitting is a
        // single-page option only.
        let double = ReaderSettings(layout: .double, firstPageAlone: true, splitWidePages: true)
        XCTAssertEqual(double.layout(for: [tall, wide, tall]).spreads, [.single(0), .single(1), .single(2)])
        let webtoon = ReaderSettings(mode: .webtoon, layout: .single, splitWidePages: true)
        XCTAssertEqual(webtoon.layout(for: [wide]).spreads, [.single(0)])
    }

    func testUnknownSizesStayWhole() {
        let s = ReaderSettings(layout: .single, splitWidePages: true)
        XCTAssertEqual(s.layout(for: [nil, nil]).spreads, [.single(0), .single(1)])
    }

    func testHalvesBelongToTheirPage() {
        let half = Spread.half(4, .left)
        XCTAssertEqual(half.pages, [4])
        XCTAssertEqual(half.first, 4)
        XCTAssertEqual(half.half, .left)
        XCTAssertNil(Spread.single(4).half)
        XCTAssertEqual(half.screenOrder(.rightToLeft), [4])
    }

    func testNavigatorWalksBothHalvesInReadingOrder() {
        let s = ReaderSettings(direction: .rightToLeft, layout: .single, splitWidePages: true)
        var nav = ReaderNavigator(sizes: [tall, wide, tall], settings: s)
        XCTAssertEqual(nav.currentSpread, .single(0))
        XCTAssertEqual(nav.turn(.left), .moved)
        XCTAssertEqual(nav.currentSpread, .half(1, .right))
        XCTAssertEqual(nav.currentPage, 1)
        XCTAssertEqual(nav.turn(.left), .moved)
        XCTAssertEqual(nav.currentSpread, .half(1, .left))
        XCTAssertEqual(nav.currentPage, 1)
        XCTAssertEqual(nav.turn(.left), .moved)
        XCTAssertEqual(nav.currentSpread, .single(2))
        XCTAssertEqual(nav.turn(.right), .moved)
        XCTAssertEqual(nav.currentSpread, .half(1, .left))
    }

    func testSecondHalfSurvivesARelayout() {
        let s = ReaderSettings(direction: .leftToRight, layout: .single, splitWidePages: true)
        var nav = ReaderNavigator(sizes: [tall, wide, nil, nil], settings: s, startPage: 1)
        _ = nav.forward()
        XCTAssertEqual(nav.currentSpread, .half(1, .right))
        // A later page turns out to be wide too (Suwayomi sizes arrive late).
        XCTAssertTrue(nav.setSize(wide, forPage: 3))
        XCTAssertEqual(nav.currentSpread, .half(1, .right))
    }

    func testTurningSplitOffKeepsThePage() {
        let s = ReaderSettings(direction: .leftToRight, layout: .single, splitWidePages: true)
        var nav = ReaderNavigator(sizes: [tall, wide, tall], settings: s, startPage: 1)
        _ = nav.forward()
        XCTAssertEqual(nav.currentSpread, .half(1, .right))
        nav.updateSettings(s.with(\.splitWidePages, false))
        XCTAssertEqual(nav.currentSpread, .single(1))
    }

    func testLastPageSplitCompletesOnlyOnItsSecondHalf() {
        let s = ReaderSettings(direction: .leftToRight, layout: .single, splitWidePages: true)
        var nav = ReaderNavigator(sizes: [tall, wide], settings: s, startPage: 1)
        XCTAssertEqual(nav.currentSpread, .half(1, .left))
        XCTAssertFalse(nav.isChapterComplete)
        _ = nav.forward()
        XCTAssertTrue(nav.isChapterComplete)
    }

    func testPreloadListsASplitPageOnce() {
        let s = ReaderSettings(direction: .leftToRight, layout: .single, splitWidePages: true)
        let nav = ReaderNavigator(sizes: [tall, wide, tall], settings: s, startPage: 1)
        XCTAssertEqual(nav.pagesToPreload(radius: 2), [1, 0, 2])
    }

    func testMenuOffersSplitInSinglePageLayoutOnly() {
        XCTAssertTrue(ReaderMenuOptions.items(for: ReaderSettings(layout: .single)).contains(.splitWidePages))
        XCTAssertFalse(ReaderMenuOptions.items(for: ReaderSettings(layout: .double)).contains(.splitWidePages))
        XCTAssertFalse(ReaderMenuOptions.items(for: ReaderSettings(mode: .webtoon, layout: .single)).contains(.splitWidePages))
    }

    // MARK: Picture controls

    func testPictureDefaults() {
        let p = PictureSettings.default
        XCTAssertTrue(p.isDefault)
        XCTAssertFalse(p.needsProcessing)
        XCTAssertEqual(ReaderSettings.default.picture, .default)
    }

    func testSteppingClampsAtTheEnds() {
        let steps = PictureSettings.brightnessSteps
        XCTAssertEqual(PictureSettings.stepped(0, in: steps, by: 1), 0.1)
        XCTAssertEqual(PictureSettings.stepped(0.3, in: steps, by: 1), 0.3)
        XCTAssertEqual(PictureSettings.stepped(-0.5, in: steps, by: -1), -0.5)
        XCTAssertFalse(PictureSettings.canStep(0.3, in: steps, by: 1))
        XCTAssertTrue(PictureSettings.canStep(0.3, in: steps, by: -1))
        XCTAssertEqual(PictureSettings.stepped(1.04, in: PictureSettings.contrastSteps, by: 1), 1.1)
    }

    func testLabels() {
        XCTAssertEqual(PictureSettings.brightnessLabel(0), "0")
        XCTAssertEqual(PictureSettings.brightnessLabel(0.1), "+10%")
        XCTAssertEqual(PictureSettings.brightnessLabel(-0.2), "−20%")
        XCTAssertEqual(PictureSettings.contrastLabel(1), "100%")
        XCTAssertEqual(PictureSettings.contrastLabel(1.3), "130%")
    }

    func testProcessingAndUpscaleRules() {
        var p = PictureSettings()
        p.sharpen = .low
        XCTAssertTrue(p.needsProcessing)
        p = PictureSettings(upscaling: .lanczos)
        XCTAssertTrue(p.needsProcessing)
        XCTAssertTrue(p.shouldUpscale(decoded: PageSize(width: 1000, height: 1500),
                                      toFill: PageSize(width: 1440, height: 2160)))
        // Already at (or within 5 % of) screen size: nothing to enlarge.
        XCTAssertFalse(p.shouldUpscale(decoded: PageSize(width: 1440, height: 2160),
                                       toFill: PageSize(width: 1440, height: 2160)))
        XCTAssertFalse(PictureSettings().shouldUpscale(decoded: PageSize(width: 100, height: 100),
                                                       toFill: PageSize(width: 1000, height: 1000)))
    }

    func testPictureTabRowsFollowTheMode() {
        XCTAssertEqual(ReaderMenuOptions.pictureItems(for: ReaderSettings(mode: .paged)), PictureMenuItem.allCases)
        XCTAssertEqual(ReaderMenuOptions.pictureItems(for: ReaderSettings(mode: .webtoon)), [.brightness, .contrast, .color])
    }

    // MARK: Saving and sync

    func testOlderSettingsWithoutNewFieldsStillDecode() throws {
        // What builds before picture controls wrote.
        let json = """
        {"mode":"paged","direction":"leftToRight","layout":"single","firstPageAlone":false,
         "shiftPairing":true,"background":"gray","webtoonWidth":0.8,"webtoonScrollStep":0.5}
        """
        let s = try JSONDecoder().decode(ReaderSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.direction, .leftToRight)
        XCTAssertEqual(s.layout, .single)
        XCTAssertTrue(s.shiftPairing)
        XCTAssertEqual(s.background, .gray)
        XCTAssertEqual(s.webtoonWidth, 0.8)
        XCTAssertFalse(s.splitWidePages)
        XCTAssertEqual(s.picture, .default)
    }

    func testUnknownValuesFallBackInsteadOfFailing() throws {
        let json = """
        {"mode":"carousel","layout":"single","picture":{"brightness":-0.2,"color":"sepia","sharpen":"high"}}
        """
        let s = try JSONDecoder().decode(ReaderSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.mode, .paged)
        XCTAssertEqual(s.layout, .single)
        XCTAssertEqual(s.picture.brightness, -0.2)
        XCTAssertEqual(s.picture.color, .normal)
        XCTAssertEqual(s.picture.sharpen, .high)
    }

    func testSettingsRoundTrip() throws {
        let s = ReaderSettings(layout: .single, splitWidePages: true,
                               picture: PictureSettings(brightness: -0.3, contrast: 1.2, color: .inverted,
                                                        sharpen: .low, upscaling: .lanczos))
        let back = try JSONDecoder().decode(ReaderSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    /// Picture and split settings ride in the existing reader settings sync
    /// domains (`readerDefaults`, `readerOverride`), so they reach other
    /// devices with no new record kind.
    func testPictureSettingsSync() {
        var source = SyncFixtures.populated()
        let p = source.activeProfile!.id
        let ref = SeriesRef(serverID: source.servers[0].id, seriesID: "1")
        let picture = PictureSettings(brightness: -0.2, contrast: 1.3, color: .grayscale, sharpen: .high, upscaling: .lanczos)
        source.setReaderSettings(ReaderSettings(layout: .single, splitWidePages: true, picture: picture), for: ref, profile: p)
        source.setDefaultReaderSettings(ReaderSettings(picture: PictureSettings(color: .inverted)), profile: p)

        let records = SyncMapper.payloads(from: source).map { key, item in
            SyncRecord(key: key, kind: item.kind, payload: item.payload, modifiedAt: Date(), deviceID: "t")
        }
        var target = AppState()
        SyncMapper.apply(SyncPatch(records: records), to: &target)

        let synced = target.readerSettings(for: ref, profile: p)
        XCTAssertTrue(synced.splitWidePages)
        XCTAssertEqual(synced.picture, picture)
        XCTAssertEqual(target.profileData[p.uuidString]?.defaultReaderSettings.picture.color, .inverted)
    }

    // MARK: Page scrubber

    func testScrubberOrderFollowsDirection() {
        XCTAssertEqual(PageScrubber.screenOrder(pageCount: 4, direction: .leftToRight), [0, 1, 2, 3])
        XCTAssertEqual(PageScrubber.screenOrder(pageCount: 4, direction: .rightToLeft), [3, 2, 1, 0])
        XCTAssertEqual(PageScrubber.screenOrder(pageCount: 0, direction: .rightToLeft), [])
    }

    func testScrubberJumpsTenAndClamps() {
        XCTAssertEqual(PageScrubber.jump(from: 5, forward: true, pageCount: 40), 15)
        XCTAssertEqual(PageScrubber.jump(from: 5, forward: false, pageCount: 40), 0)
        XCTAssertEqual(PageScrubber.jump(from: 35, forward: true, pageCount: 40), 39)
        XCTAssertEqual(PageScrubber.jump(from: 0, forward: true, pageCount: 0), 0)
    }

    func testScrubberNeighborsFollowReadingDirection() {
        XCTAssertEqual(PageScrubber.neighbor(of: 3, screen: .left, direction: .rightToLeft, pageCount: 10), 4)
        XCTAssertEqual(PageScrubber.neighbor(of: 3, screen: .left, direction: .leftToRight, pageCount: 10), 2)
        XCTAssertNil(PageScrubber.neighbor(of: 9, screen: .right, direction: .leftToRight, pageCount: 10))
    }

    func testScrubberProgressAndLabel() {
        XCTAssertEqual(PageScrubber.progress(page: 0, pageCount: 5), 0)
        XCTAssertEqual(PageScrubber.progress(page: 4, pageCount: 5), 1)
        XCTAssertEqual(PageScrubber.progress(page: 2, pageCount: 5), 0.5)
        XCTAssertEqual(PageScrubber.progress(page: 0, pageCount: 1), 1)
        XCTAssertEqual(PageScrubber.label(page: 11, pageCount: 40), "Page 12 of 40")
        XCTAssertEqual(PageScrubber.label(page: 0, pageCount: 0), "")
    }

    func testThumbnailWidths() {
        XCTAssertEqual(PageScrubber.thumbnailWidth(height: 200, size: tall), 133)
        XCTAssertEqual(PageScrubber.thumbnailWidth(height: 200, size: nil), 140)
        // A very wide panorama is capped at two placeholder page widths.
        XCTAssertEqual(PageScrubber.thumbnailWidth(height: 200, size: PageSize(width: 5000, height: 1000)), 280)
    }
}
