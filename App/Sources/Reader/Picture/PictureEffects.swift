import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import MangaCore

extension View {
    /// Brightness, contrast and color mode from the reader's picture
    /// controls. These are GPU view effects, so they apply instantly and
    /// work on the paged reader's images and the webtoon strip alike.
    func pictureAdjustments(_ picture: PictureSettings) -> some View {
        self
            .brightness(picture.clampedBrightness)
            .contrast(picture.clampedContrast)
            .grayscale(picture.color == .normal ? 0 : 1)
            .modifier(InvertIf(on: picture.color == .inverted))
    }
}

private struct InvertIf: ViewModifier {
    let on: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if on { content.colorInvert() } else { content }
    }
}

/// Re-renders page images for the picture controls that need real pixels:
/// Lanczos upscaling (for scans smaller than a 4K screen) and luminance
/// sharpening. Runs Core Image on the GPU (Metal) off the main thread and
/// caches results, so turning back to a page doesn't redo the work.
final class PictureProcessor: @unchecked Sendable {
    static let shared = PictureProcessor()

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let cache = NSCache<NSString, CGImageBox>()

    private final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    init() {
        cache.countLimit = 12
    }

    struct Request: Hashable {
        var url: URL
        var targetPixels: PageSize
        var sharpen: PictureSharpen
        var upscale: Bool

        var key: NSString {
            "\(url.absoluteString)|\(Int(targetPixels.width))x\(Int(targetPixels.height))|\(sharpen.rawValue)|\(upscale)" as NSString
        }
    }

    /// The request for a page, or nil when the settings leave it alone.
    static func request(for url: URL, image: CGImage, picture: PictureSettings, framePixels: CGSize) -> Request? {
        guard picture.needsProcessing, framePixels.width >= 1, framePixels.height >= 1 else { return nil }
        let decoded = PageSize(width: Double(image.width), height: Double(image.height))
        let frame = PageSize(width: framePixels.width.rounded(), height: framePixels.height.rounded())
        let upscale = picture.shouldUpscale(decoded: decoded, toFill: frame)
        guard upscale || picture.sharpen != .off else { return nil }
        return Request(url: url, targetPixels: upscale ? frame : decoded, sharpen: picture.sharpen, upscale: upscale)
    }

    func cached(_ request: Request) -> CGImage? {
        cache.object(forKey: request.key)?.image
    }

    func process(_ image: CGImage, _ request: Request) async -> CGImage? {
        if let hit = cached(request) { return hit }
        let result = await Task.detached(priority: .userInitiated) { [context] () -> CGImage? in
            var output = CIImage(cgImage: image)
            if request.upscale {
                let scale = request.targetPixels.height / Double(image.height)
                let aspect = (request.targetPixels.width / Double(image.width)) / scale
                let lanczos = CIFilter.lanczosScaleTransform()
                lanczos.inputImage = output
                lanczos.scale = Float(scale)
                lanczos.aspectRatio = Float(aspect)
                if let scaled = lanczos.outputImage { output = scaled }
            }
            if request.sharpen != .off {
                let sharpen = CIFilter.sharpenLuminance()
                sharpen.inputImage = output
                sharpen.sharpness = Float(request.sharpen.amount)
                sharpen.radius = 1.5
                if let sharpened = sharpen.outputImage { output = sharpened }
            }
            let extent = output.extent.integral.intersection(
                CGRect(x: 0, y: 0, width: request.targetPixels.width, height: request.targetPixels.height))
            guard !Task.isCancelled, !extent.isEmpty else { return nil }
            return context.createCGImage(output, from: extent)
        }.value
        if let result { cache.setObject(CGImageBox(result), forKey: request.key) }
        return result
    }
}
