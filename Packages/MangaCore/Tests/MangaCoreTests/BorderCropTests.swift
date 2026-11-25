import XCTest
import CoreGraphics
@testable import MangaCore

final class BorderCropTests: XCTestCase {
    /// A `w × h` grayscale page of `background` with a `content` rectangle
    /// (x, y, width, height in pixels) filled with mid-gray "art".
    private func page(_ w: Int, _ h: Int, background: UInt8, content: (Int, Int, Int, Int)?,
                      art: UInt8 = 120) -> [UInt8] {
        var px = [UInt8](repeating: background, count: w * h)
        if let (cx, cy, cw, ch) = content {
            for y in cy..<(cy + ch) { for x in cx..<(cx + cw) { px[y * w + x] = art } }
        }
        return px
    }

    func testWhiteMarginsAreFound() {
        // 200×300 page, art at x 20..<180, y 30..<270.
        let px = page(200, 300, background: 255, content: (20, 30, 160, 240))
        let c = BorderCropDetector.detect(luma: px, width: 200, height: 300)
        // One sample of margin is left on each cropped side.
        XCTAssertEqual(c.left, 19.0 / 200, accuracy: 1e-9)
        XCTAssertEqual(c.right, 19.0 / 200, accuracy: 1e-9)
        XCTAssertEqual(c.top, 29.0 / 300, accuracy: 1e-9)
        XCTAssertEqual(c.bottom, 29.0 / 300, accuracy: 1e-9)
    }

    func testBlackMarginsAreFound() {
        let px = page(200, 300, background: 0, content: (40, 10, 120, 280), art: 200)
        let c = BorderCropDetector.detect(luma: px, width: 200, height: 300)
        XCTAssertEqual(c.left, 39.0 / 200, accuracy: 1e-9)
        XCTAssertEqual(c.right, 39.0 / 200, accuracy: 1e-9)
        XCTAssertEqual(c.top, 9.0 / 300, accuracy: 1e-9)
        XCTAssertEqual(c.bottom, 9.0 / 300, accuracy: 1e-9)
    }

    func testFullBleedArtIsLeftAlone() {
        let px = page(200, 300, background: 120, content: nil)
        XCTAssertEqual(BorderCropDetector.detect(luma: px, width: 200, height: 300), .zero)
    }

    func testArtBleedingOffOneSideOnlyCropsTheOthers() {
        // Art touches the right edge; white margins elsewhere.
        let px = page(200, 300, background: 255, content: (30, 30, 170, 240))
        let c = BorderCropDetector.detect(luma: px, width: 200, height: 300)
        XCTAssertEqual(c.right, 0)
        XCTAssertGreaterThan(c.left, 0.1)
        XCTAssertGreaterThan(c.top, 0.05)
    }

    func testDustInTheMarginIsIgnored() {
        var px = page(200, 300, background: 255, content: (20, 30, 160, 240))
        // A speck in the top margin.
        px[5 * 200 + 100] = 0
        let c = BorderCropDetector.detect(luma: px, width: 200, height: 300)
        XCTAssertEqual(c.top, 29.0 / 300, accuracy: 1e-9)
    }

    func testOffWhitePaperCountsAsWhite() {
        let px = page(200, 300, background: 236, content: (20, 30, 160, 240))
        XCTAssertGreaterThan(BorderCropDetector.detect(luma: px, width: 200, height: 300).top, 0)
    }

    func testCropIsCappedPerSide() {
        // Art in a band near the bottom: the top crop stops at maxSide.
        let px = page(200, 300, background: 255, content: (0, 200, 200, 90))
        let c = BorderCropDetector.detect(luma: px, width: 200, height: 300)
        let maxRows = Int(300 * BorderCropDetector.Options().maxSide)
        XCTAssertEqual(c.top, Double(maxRows - 1) / 300, accuracy: 1e-9)
    }

    func testNearlyBlankPageIsNotCropped() {
        // A small caption in the middle of a blank page.
        let px = page(200, 300, background: 255, content: (90, 140, 20, 10))
        XCTAssertEqual(BorderCropDetector.detect(luma: px, width: 200, height: 300), .zero)
    }

    func testTinyMarginsAreIgnored() {
        let px = page(400, 600, background: 255, content: (1, 1, 398, 598))
        XCTAssertEqual(BorderCropDetector.detect(luma: px, width: 400, height: 600), .zero)
    }

    func testMixedEdgeIsLeftAlone() {
        // Left half white, right half black: no single border color.
        var px = [UInt8](repeating: 255, count: 200 * 300)
        for y in 0..<300 { for x in 100..<200 { px[y * 200 + x] = 0 } }
        XCTAssertEqual(BorderCropDetector.detect(luma: px, width: 200, height: 300), .zero)
    }

    func testTooSmallInputIsLeftAlone() {
        XCTAssertEqual(BorderCropDetector.detect(luma: [255, 255], width: 1, height: 2), .zero)
        XCTAssertEqual(BorderCropDetector.detect(luma: [], width: 100, height: 100), .zero)
    }

    func testDetectsOnARealCGImage() throws {
        // 800×1200 RGB page, white with a dark block at 100..<700 × 150..<1050.
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 800, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1200))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1))
        // CoreGraphics' origin is bottom-left: y 150 from the bottom.
        ctx.fill(CGRect(x: 100, y: 150, width: 600, height: 900))
        let image = try XCTUnwrap(ctx.makeImage())
        let c = BorderCropDetector.detect(in: image)
        // 1/8 per side horizontally, 1/8 top and bottom, within a sample or two.
        let sample = 1.0 / Double(BorderCropDetector.sampleSize)
        XCTAssertEqual(c.left, 0.125, accuracy: 3 * sample)
        XCTAssertEqual(c.right, 0.125, accuracy: 3 * sample)
        XCTAssertEqual(c.top, 0.125, accuracy: 3 * sample)
        XCTAssertEqual(c.bottom, 0.125, accuracy: 3 * sample)
    }

    func testTopAndBottomAreNotSwapped() throws {
        // More margin at the top (300) than the bottom (60).
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 1200))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 40, y: 60, width: 320, height: 840))   // bottom-left origin
        let c = BorderCropDetector.detect(in: try XCTUnwrap(ctx.makeImage()))
        XCTAssertGreaterThan(c.top, c.bottom)
        XCTAssertEqual(c.top, 0.25, accuracy: 0.02)
        XCTAssertEqual(c.bottom, 0.05, accuracy: 0.02)
    }

    func testCroppedSize() {
        let c = CropInsets(top: 0.1, left: 0.05, bottom: 0.1, right: 0.05)
        let s = c.cropped(PageSize(width: 1000, height: 1500))
        XCTAssertEqual(s.width, 900, accuracy: 1e-9)
        XCTAssertEqual(s.height, 1200, accuracy: 1e-9)
    }

    // MARK: Spreads

    func testSinglePageUsesItsOwnCrop() {
        let c = CropInsets(top: 0.1, left: 0.2, bottom: 0.05, right: 0.1)
        XCTAssertEqual(SpreadCrop.insets([c]), [c])
        XCTAssertEqual(SpreadCrop.insets([nil]), [.zero])
    }

    func testSpreadSharesTopAndBottomAndKeepsInnerEdges() {
        let left = CropInsets(top: 0.1, left: 0.08, bottom: 0.04, right: 0.07)
        let right = CropInsets(top: 0.06, left: 0.09, bottom: 0.05, right: 0.03)
        let result = SpreadCrop.insets([left, right])
        XCTAssertEqual(result[0], CropInsets(top: 0.06, left: 0.08, bottom: 0.04, right: 0))
        XCTAssertEqual(result[1], CropInsets(top: 0.06, left: 0, bottom: 0.04, right: 0.03))
    }

    func testSpreadWithOneUnknownCropDoesNotCropVertically() {
        let left = CropInsets(top: 0.1, left: 0.08, bottom: 0.04, right: 0.07)
        let result = SpreadCrop.insets([left, nil])
        XCTAssertEqual(result[0], CropInsets(top: 0, left: 0.08, bottom: 0, right: 0))
        XCTAssertEqual(result[1], .zero)
    }

    func testCroppedSpreadStaysSeamless() {
        // Two cropped pages laid out together still touch exactly.
        let sizes = [PageSize(width: 777, height: 1111), PageSize(width: 701, height: 1093)]
        let crops = SpreadCrop.insets([CropInsets(top: 0.05, left: 0.1, bottom: 0.05, right: 0.02),
                                       CropInsets(top: 0.07, left: 0.03, bottom: 0.06, right: 0.1)])
        let effective = zip(sizes, crops).map { $1.cropped($0) }
        let frames = SpreadGeometry.canvas(for: effective, in: 1920, 1080, fit: .screen, scale: 2).frames
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].x + frames[0].width, frames[1].x, accuracy: 1e-9)
        XCTAssertEqual(frames[0].height, frames[1].height)
    }
}
