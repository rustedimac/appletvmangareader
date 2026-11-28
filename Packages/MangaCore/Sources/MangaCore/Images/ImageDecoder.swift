import Foundation
import CoreGraphics
import ImageIO

/// ImageIO decoding with downsampling, so a 2,000 × 3,000 page drawn at
/// 1,080 pixels tall never sits in memory at full size.
enum ImageDecoder {
    /// Largest texture side the Apple TV GPU accepts.
    static let maxTextureSide = 16_384

    /// Original pixel size from the header, with EXIF rotation applied.
    static func pixelSize(of data: Data) -> PageSize? {
        if let pdf = OnePagePDF(data) { return pdf.pixelSize }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return pixelSize(of: source)
    }

    static func pixelSize(of source: CGImageSource) -> PageSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        // Orientations 5–8 are rotated 90°.
        return (5...8).contains(orientation) ? PageSize(width: h, height: w) : PageSize(width: w, height: h)
    }

    /// The longest side, in pixels, to decode `original` at so it still looks
    /// sharp drawn into `target`.
    static func maxPixelSize(original: PageSize, target: CGSize?, scaling: ImageScaling) -> Int {
        let longest = max(original.width, original.height)
        var scale = 1.0
        if let target {
            var ratios: [Double] = []
            if target.width > 0, target.width.isFinite { ratios.append(Double(target.width) / original.width) }
            if target.height > 0, target.height.isFinite { ratios.append(Double(target.height) / original.height) }
            if !ratios.isEmpty {
                let r = scaling == .fit ? ratios.min()! : ratios.max()!
                scale = min(1, r)
            }
        }
        let pixels = min(longest * scale, Double(maxTextureSide))
        return max(1, Int(pixels.rounded(.up)))
    }

    static func decode(_ data: Data, targetSize: CGSize?, scaling: ImageScaling) throws -> LoadedImage {
        if let pdf = OnePagePDF(data) {
            let longest = maxPixelSize(original: pdf.pixelSize, target: targetSize, scaling: scaling)
            guard let image = pdf.render(longSide: Double(longest)) else { throw ImagePipelineError.undecodable }
            return LoadedImage(cgImage: image, pixelSize: pdf.pixelSize)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let original = pixelSize(of: source) else {
            throw ImagePipelineError.undecodable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(original: original, target: targetSize, scaling: scaling),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImagePipelineError.undecodable
        }
        return LoadedImage(cgImage: image, pixelSize: original)
    }
}

/// A page a server sent as a PDF instead of a picture (Codex sends PDF
/// books' pages this way whatever is asked for). Its first page is drawn
/// with CoreGraphics, the same way `LocalPDFRenderer` draws downloaded PDFs.
struct OnePagePDF {
    let page: CGPDFPage
    /// The page's size at `LocalPDFRenderer.longSide`, which stands in for
    /// a pixel size (spread pairing and webtoon heights only need the shape).
    let pixelSize: PageSize

    init?(_ data: Data) {
        guard data.starts(with: Array("%PDF".utf8)),
              let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider),
              !doc.isEncrypted || doc.unlockWithPassword(""),
              let page = doc.page(at: 1),
              let size = LocalPDFRenderer.size(of: page) else { return nil }
        self.page = page
        let scale = LocalPDFRenderer.longSide / max(size.width, size.height)
        pixelSize = PageSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    func render(longSide: Double) -> CGImage? {
        LocalPDFRenderer.image(of: page, longSide: longSide)
    }
}
