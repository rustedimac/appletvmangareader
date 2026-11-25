import Foundation
import CoreGraphics

/// How much of each side of a page is margin, as fractions of the page's
/// width (left, right) or height (top, bottom). Resolution independent, so
/// insets found on a small thumbnail apply to the full image.
public struct CropInsets: Codable, Hashable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = CropInsets()

    public var isZero: Bool { top == 0 && left == 0 && bottom == 0 && right == 0 }

    /// Fraction of the width and height that stays visible.
    public var visibleWidth: Double { max(0.01, 1 - left - right) }
    public var visibleHeight: Double { max(0.01, 1 - top - bottom) }

    /// The page's size once these margins are trimmed.
    public func cropped(_ size: PageSize) -> PageSize {
        PageSize(width: size.width * visibleWidth, height: size.height * visibleHeight)
    }
}

/// Finds plain white or black margins around a scanned page, the way
/// Mihon's and Kavita's "crop borders" do, so the art can use the screen.
///
/// The detector works on an 8-bit grayscale thumbnail. It decides the
/// border color from the page's outer edge (mostly white or mostly black;
/// anything else is left alone), then walks in from each side while whole
/// rows or columns are that color, allowing a little dust. It stays
/// conservative: it never takes more than `maxSide` of a side, it leaves
/// one sample of margin so anti-aliased edges aren't clipped, and it gives
/// up (no crop) on nearly blank pages, where cropping would blow a small
/// caption up to full screen.
public enum BorderCropDetector {
    public struct Options: Hashable, Sendable {
        /// How far from pure white (255) or black (0) still counts as border.
        public var tolerance: UInt8 = 40
        /// Share of a row or column that may be non-border (specks, dust).
        public var noise: Double = 0.01
        /// Share of the outer edge that must be the border color.
        public var edgeAgreement: Double = 0.6
        /// Most that can be cropped from any one side.
        public var maxSide: Double = 0.35
        /// Crops smaller than this (per side) are ignored.
        public var minSide: Double = 0.005
        /// Pages whose content is smaller than this in either direction are
        /// treated as blank and not cropped.
        public var minContent: Double = 0.2

        public init() {}
    }

    public enum BorderColor: Sendable { case white, black }

    /// Longest side of the thumbnail detection runs on.
    public static let sampleSize = 256

    /// Detects margins on grayscale pixels, row-major, `width × height`.
    public static func detect(luma: [UInt8], width: Int, height: Int, options: Options = Options()) -> CropInsets {
        guard width >= 8, height >= 8, luma.count >= width * height else { return .zero }
        guard let color = borderColor(luma: luma, width: width, height: height, options: options) else { return .zero }
        let tol = Int(options.tolerance)
        @inline(__always) func isBorder(_ v: UInt8) -> Bool {
            color == .white ? Int(v) >= 255 - tol : Int(v) <= tol
        }
        func rowIsBorder(_ y: Int, _ x0: Int, _ x1: Int) -> Bool {
            let allowed = Int(Double(x1 - x0) * options.noise)
            var bad = 0
            let base = y * width
            for x in x0..<x1 where !isBorder(luma[base + x]) {
                bad += 1
                if bad > allowed { return false }
            }
            return true
        }
        func columnIsBorder(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            let allowed = Int(Double(y1 - y0) * options.noise)
            var bad = 0
            for y in y0..<y1 where !isBorder(luma[y * width + x]) {
                bad += 1
                if bad > allowed { return false }
            }
            return true
        }

        let maxRows = Int(Double(height) * options.maxSide)
        let maxCols = Int(Double(width) * options.maxSide)
        var top = 0
        while top < maxRows, rowIsBorder(top, 0, width) { top += 1 }
        var bottom = 0
        while bottom < maxRows, rowIsBorder(height - 1 - bottom, 0, width) { bottom += 1 }
        let y0 = top, y1 = height - bottom
        guard y1 - y0 > 0 else { return .zero }
        var left = 0
        while left < maxCols, columnIsBorder(left, y0, y1) { left += 1 }
        var right = 0
        while right < maxCols, columnIsBorder(width - 1 - right, y0, y1) { right += 1 }

        // Leave one sample of margin on cropped sides.
        top = max(0, top - 1); bottom = max(0, bottom - 1)
        left = max(0, left - 1); right = max(0, right - 1)

        var insets = CropInsets(top: Double(top) / Double(height),
                                left: Double(left) / Double(width),
                                bottom: Double(bottom) / Double(height),
                                right: Double(right) / Double(width))
        if insets.visibleWidth < options.minContent || insets.visibleHeight < options.minContent { return .zero }
        // A page that is nearly all margin (a blank or a short caption).
        if insets.visibleWidth * insets.visibleHeight < options.minContent { return .zero }
        func floor(_ v: Double) -> Double { v < options.minSide ? 0 : v }
        insets = CropInsets(top: floor(insets.top), left: floor(insets.left),
                            bottom: floor(insets.bottom), right: floor(insets.right))
        return insets
    }

    /// White or black if most of the page's outer edge is that color.
    static func borderColor(luma: [UInt8], width: Int, height: Int, options: Options) -> BorderColor? {
        let tol = Int(options.tolerance)
        var white = 0, black = 0, total = 0
        func sample(_ v: UInt8) {
            total += 1
            if Int(v) >= 255 - tol { white += 1 } else if Int(v) <= tol { black += 1 }
        }
        for x in 0..<width {
            sample(luma[x])
            sample(luma[(height - 1) * width + x])
        }
        for y in 1..<(height - 1) {
            sample(luma[y * width])
            sample(luma[y * width + width - 1])
        }
        guard total > 0 else { return nil }
        if Double(white) / Double(total) >= options.edgeAgreement { return .white }
        if Double(black) / Double(total) >= options.edgeAgreement { return .black }
        return nil
    }

    /// Detects margins on a decoded image by drawing it into a small
    /// grayscale thumbnail first (a few hundred microseconds per page).
    public static func detect(in image: CGImage, options: Options = Options()) -> CropInsets {
        guard let (luma, w, h) = grayscaleThumbnail(image) else { return .zero }
        return detect(luma: luma, width: w, height: h, options: options)
    }

    static func grayscaleThumbnail(_ image: CGImage) -> ([UInt8], Int, Int)? {
        guard image.width > 0, image.height > 0 else { return nil }
        let scale = min(1, Double(sampleSize) / Double(max(image.width, image.height)))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // Transparent areas read as white, like paper.
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (pixels, w, h) : nil
    }
}

/// Crop insets for the pages of one spread, in screen order (left to right).
///
/// A single page uses its own insets. In a two-page spread the pages are
/// shown at one height and touching, so the halves of a printed spread line
/// up. To keep that true after cropping, both pages share one top and one
/// bottom crop (the smaller of the two, so no art is lost), and the inner
/// edges where the pages meet are never cropped. Only the outer sides use
/// each page's own crop.
public enum SpreadCrop {
    public static func insets(_ crops: [CropInsets?]) -> [CropInsets] {
        let pages = crops.map { $0 ?? .zero }
        guard pages.count == 2 else { return pages }
        let top = min(pages[0].top, pages[1].top)
        let bottom = min(pages[0].bottom, pages[1].bottom)
        return [
            CropInsets(top: top, left: pages[0].left, bottom: bottom, right: 0),
            CropInsets(top: top, left: 0, bottom: bottom, right: pages[1].right),
        ]
    }
}
