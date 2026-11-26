import XCTest
@testable import MangaCore

final class PagedViewportTests: XCTestCase {
    private let screen = Extent(width: 1920, height: 1080)
    private let tall = PageSize(width: 400, height: 600)

    // MARK: Fit modes

    func testFitScreenMatchesSpreadFrames() {
        let sizes: [PageSize?] = [PageSize(width: 777, height: 1111), PageSize(width: 701, height: 1093)]
        let canvas = SpreadGeometry.canvas(for: sizes, in: 1920, 1080, fit: .screen, scale: 2)
        XCTAssertEqual(canvas.frames, SpreadGeometry.frames(for: sizes, in: 1920, 1080, scale: 2))
        XCTAssertEqual(canvas.size, screen)
    }

    func testFitWidthMakesATallCanvas() {
        let canvas = SpreadGeometry.canvas(for: [tall], in: 1920, 1080, fit: .width)
        XCTAssertEqual(canvas.size, Extent(width: 1920, height: 2880))
        XCTAssertEqual(canvas.frames, [PageFrame(x: 0, y: 0, width: 1920, height: 2880)])
    }

    func testFitWidthOnAWideSpreadIsCentered() {
        let canvas = SpreadGeometry.canvas(for: [PageSize(width: 3000, height: 1000)], in: 1920, 1080, fit: .width)
        XCTAssertEqual(canvas.size, screen)
        XCTAssertEqual(canvas.frames, [PageFrame(x: 0, y: 220, width: 1920, height: 640)])
    }

    func testFitHeightMakesAWideCanvasForSpreads() {
        let wide = PageSize(width: 900, height: 600)
        let canvas = SpreadGeometry.canvas(for: [wide, wide], in: 1920, 1080, fit: .height, scale: 2)
        XCTAssertEqual(canvas.size, Extent(width: 3240, height: 1080))
        XCTAssertEqual(canvas.frames[0], PageFrame(x: 0, y: 0, width: 1620, height: 1080))
        XCTAssertEqual(canvas.frames[1].x, 1620)   // still touching
    }

    func testFitHeightOnATallPageIsLikeFitScreen() {
        let canvas = SpreadGeometry.canvas(for: [tall], in: 1920, 1080, fit: .height)
        XCTAssertEqual(canvas.size, screen)
        XCTAssertEqual(canvas.frames, [PageFrame(x: 600, y: 0, width: 720, height: 1080)])
    }

    func testFitWidthTwoPagesStaySeamless() {
        let sizes: [PageSize?] = [PageSize(width: 777, height: 1111), PageSize(width: 701, height: 1093)]
        let frames = SpreadGeometry.canvas(for: sizes, in: 1920, 1080, fit: .width, scale: 2).frames
        XCTAssertLessThanOrEqual(frames[0].x, 1)
        XCTAssertEqual(frames[0].x + frames[0].width, frames[1].x, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(frames[1].x + frames[1].width, 1920)
        XCTAssertEqual(frames[0].height, frames[1].height)
    }

    func testEmptyCanvas() {
        XCTAssertEqual(SpreadGeometry.canvas(for: [], in: 100, 50, fit: .width).frames, [])
    }

    // MARK: Viewport

    func testTravelAndOffset() {
        let canvas = Extent(width: 1920, height: 2880)
        let v = PagedViewport(zoom: 1, x: 0.5, y: 0.5)
        XCTAssertEqual(v.travel(canvas: canvas, screen: screen), Extent(width: 0, height: 1800))
        let o = v.offset(canvas: canvas, screen: screen)
        XCTAssertEqual(o.x, 0)
        XCTAssertEqual(o.y, 900)
    }

    func testPanningClampsAtEdges() {
        let canvas = Extent(width: 1920, height: 2880)
        var v = PagedViewport.start(.rightToLeft)
        XCTAssertFalse(v.canPan(.up, canvas: canvas, screen: screen))
        XCTAssertTrue(v.canPan(.down, canvas: canvas, screen: screen))
        XCTAssertFalse(v.canPan(.left, canvas: canvas, screen: screen))
        v = v.panned(.down, step: 0.8, canvas: canvas, screen: screen)
        XCTAssertEqual(v.y, 864.0 / 1800, accuracy: 1e-9)
        v = v.panned(.down, step: 0.8, canvas: canvas, screen: screen)
        v = v.panned(.down, step: 0.8, canvas: canvas, screen: screen)
        XCTAssertEqual(v.y, 1)
        XCTAssertFalse(v.canPan(.down, canvas: canvas, screen: screen))
    }

    func testZoomKeepsTheCenter() {
        let v = PagedViewport(zoom: 1, x: 0.5, y: 0.5).zoomed(to: 2, canvas: screen, screen: screen)
        XCTAssertEqual(v.zoom, 2)
        XCTAssertEqual(v.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(v.travel(canvas: screen, screen: screen), Extent(width: 1920, height: 1080))
        // Zooming back out returns to an unpannable view.
        let out = v.zoomed(to: 1, canvas: screen, screen: screen)
        XCTAssertFalse(out.isZoomed)
        XCTAssertEqual(out.travel(canvas: screen, screen: screen), .zero)
    }

    func testZoomFromAPannedViewKeepsWhatWasCentered() {
        // Fit width, scrolled to the bottom: the bottom stays in view at 2×.
        let canvas = Extent(width: 1920, height: 2880)
        let v = PagedViewport(zoom: 1, x: 0.5, y: 1).zoomed(to: 2, canvas: canvas, screen: screen)
        // Center was at canvas y 2340 of 2880; at 2× that's 4680 of 5760.
        let o = v.offset(canvas: canvas, screen: screen)
        XCTAssertEqual(o.y + 540, 4680, accuracy: 1)
        XCTAssertEqual(o.x + 960, 1920, accuracy: 1)
    }

    func testStartAndEndFollowReadingDirection() {
        XCTAssertEqual(PagedViewport.start(.rightToLeft), PagedViewport(zoom: 1, x: 1, y: 0))
        XCTAssertEqual(PagedViewport.start(.leftToRight), PagedViewport(zoom: 1, x: 0, y: 0))
        XCTAssertEqual(PagedViewport.end(.rightToLeft), PagedViewport(zoom: 1, x: 0, y: 1))
        XCTAssertEqual(PagedViewport.end(.leftToRight), PagedViewport(zoom: 1, x: 1, y: 1))
    }

    // MARK: Remote

    private func action(_ press: PanDirection, _ v: PagedViewport, canvas: Extent? = nil,
                        _ direction: ReadingDirection = .rightToLeft) -> PagedRemoteAction {
        PagedRemote.action(for: press, viewport: v, canvas: canvas ?? screen, screen: screen, direction: direction)
    }

    func testFitScreenTurnsAndOpensMenu() {
        let v = PagedViewport.start(.rightToLeft)
        XCTAssertEqual(action(.left, v), .turn(.left))
        XCTAssertEqual(action(.right, v), .turn(.right))
        XCTAssertEqual(action(.down, v), .openMenu)
        XCTAssertEqual(action(.up, v), PagedRemoteAction.none)
    }

    func testFitWidthScrollsDownBeforeTurning() {
        let canvas = Extent(width: 1920, height: 2880)
        let top = PagedViewport.start(.rightToLeft)
        // Forward (left in right-to-left) scrolls down first.
        guard case .pan(let next) = action(.left, top, canvas: canvas) else { return XCTFail() }
        XCTAssertGreaterThan(next.y, 0)
        // Backward at the top turns back.
        XCTAssertEqual(action(.right, top, canvas: canvas), .turn(.right))
        // At the bottom forward turns, backward scrolls up, down does nothing.
        let bottom = PagedViewport(zoom: 1, x: 0.5, y: 1)
        XCTAssertEqual(action(.left, bottom, canvas: canvas), .turn(.left))
        guard case .pan(let up) = action(.right, bottom, canvas: canvas) else { return XCTFail() }
        XCTAssertLessThan(up.y, 1)
        XCTAssertEqual(action(.down, bottom, canvas: canvas), PagedRemoteAction.none)
        guard case .pan = action(.down, top, canvas: canvas) else { return XCTFail() }
    }

    func testZoomedPagePansSidewaysThenTurnsAtTheEdge() {
        // 2× on a screen-sized canvas, right to left, starting top right.
        var v = PagedViewport.start(.rightToLeft).zoomed(to: 2, canvas: screen, screen: screen)
        v.x = 1; v.y = 0
        guard case .pan(let a) = action(.left, v) else { return XCTFail() }
        XCTAssertLessThan(a.x, 1)
        XCTAssertEqual(a.y, 0)
        // At the left edge of the top half, forward turns the page; it
        // doesn't drop down a row.
        XCTAssertEqual(action(.left, PagedViewport(zoom: 2, x: 0, y: 0)), .turn(.left))
        XCTAssertEqual(action(.left, PagedViewport(zoom: 2, x: 0, y: 0.4)), .turn(.left))
        // Backward at the right edge turns back, wherever it is vertically.
        XCTAssertEqual(action(.right, PagedViewport(zoom: 2, x: 1, y: 0.6)), .turn(.right))
        // Away from the edge it still pans.
        guard case .pan(let back) = action(.right, PagedViewport(zoom: 2, x: 0, y: 0)) else { return XCTFail() }
        XCTAssertGreaterThan(back.x, 0)
        XCTAssertEqual(back.y, 0)
        // Up and down pan; zoomed, down at the bottom never opens the menu.
        guard case .pan(let down) = action(.down, PagedViewport(zoom: 2, x: 0, y: 0)) else { return XCTFail() }
        XCTAssertGreaterThan(down.y, 0)
        XCTAssertEqual(action(.down, PagedViewport(zoom: 2, x: 0, y: 1)), PagedRemoteAction.none)
    }

    func testFitHeightTurnsAtTheSideEdge() {
        // A spread wider than the screen at Fit Height: no vertical travel.
        let canvas = Extent(width: 3000, height: screen.height)
        XCTAssertEqual(action(.left, PagedViewport(zoom: 1, x: 0, y: 0), canvas: canvas), .turn(.left))
        guard case .pan = action(.left, PagedViewport(zoom: 1, x: 1, y: 0), canvas: canvas) else { return XCTFail() }
    }

    func testLeftToRightZoomPansRightFirst() {
        let v = PagedViewport(zoom: 2, x: 0, y: 0)
        guard case .pan(let a) = action(.right, v, .leftToRight) else { return XCTFail() }
        XCTAssertGreaterThan(a.x, 0)
        XCTAssertEqual(action(.right, PagedViewport(zoom: 2, x: 1, y: 1), .leftToRight), .turn(.right))
    }

    // MARK: Touch-surface drag

    func testDragFollowsTheFingerAndClamps() {
        let screen = Extent(width: 1000, height: 500)
        let canvas = Extent(width: 1000, height: 500)
        let v = PagedViewport(zoom: 2, x: 0.5, y: 0.5)   // travel 1000 x 500
        // Finger right 250 pt: the view moves left by a quarter of the travel.
        let right = v.dragged(dx: 250, dy: 0, canvas: canvas, screen: screen)
        XCTAssertEqual(right.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(right.y, 0.5, accuracy: 1e-9)
        // Finger up 100 pt: the view moves down.
        let up = v.dragged(dx: 0, dy: -100, canvas: canvas, screen: screen)
        XCTAssertEqual(up.y, 0.7, accuracy: 1e-9)
        // Gain scales the move; edges clamp.
        XCTAssertEqual(v.dragged(dx: 250, dy: 0, gain: 2, canvas: canvas, screen: screen).x, 0, accuracy: 1e-9)
        XCTAssertEqual(v.dragged(dx: -5000, dy: 5000, canvas: canvas, screen: screen).x, 1)
        XCTAssertEqual(v.dragged(dx: -5000, dy: 5000, canvas: canvas, screen: screen).y, 0)
        XCTAssertEqual(v.dragged(dx: 0, dy: 0, canvas: canvas, screen: screen).zoom, 2)
    }

    func testDragOnlyMovesAxesWithRoom() {
        // Fit Width: taller than the screen, no sideways travel.
        let screen = Extent(width: 1000, height: 500)
        let canvas = Extent(width: 1000, height: 1500)
        let v = PagedViewport(zoom: 1, x: 0.5, y: 0)
        XCTAssertTrue(v.canDrag(canvas: canvas, screen: screen))
        let moved = v.dragged(dx: 300, dy: -500, canvas: canvas, screen: screen)
        XCTAssertEqual(moved.x, 0.5)
        XCTAssertEqual(moved.y, 0.5, accuracy: 1e-9)
        XCTAssertFalse(PagedViewport().canDrag(canvas: screen, screen: screen))
    }
}

