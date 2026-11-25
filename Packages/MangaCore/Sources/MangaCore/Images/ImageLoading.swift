import Foundation
import CoreGraphics

/// How the image will be drawn into `targetSize`, which decides how far it
/// can be downsampled.
public enum ImageScaling: Sendable, Hashable {
    /// The whole image fits inside the target (aspect fit). Pages use this.
    case fit
    /// The image covers the target and is cropped (aspect fill). Posters.
    case fill
}

/// A decoded image plus the size of the original file, which readers need
/// for spread pairing and webtoon heights (Suwayomi doesn't send sizes).
public struct LoadedImage: @unchecked Sendable {
    public let image: PlatformImage
    public let cgImage: CGImage
    /// Pixel size of the original image on the server (orientation applied).
    public let pixelSize: PageSize
    /// Pixel size of `image` after downsampling.
    public var decodedSize: PageSize { PageSize(width: Double(cgImage.width), height: Double(cgImage.height)) }

    public init(cgImage: CGImage, pixelSize: PageSize) {
        self.cgImage = cgImage
        self.image = PlatformImage.make(cgImage)
        self.pixelSize = pixelSize
    }
}

public enum ImagePipelineError: Error, Equatable, Sendable, LocalizedError {
    /// The server sent bytes that aren't an image ImageIO can read.
    case undecodable

    public var errorDescription: String? {
        switch self {
        case .undecodable: return "The server sent an image that couldn't be read."
        }
    }
}

/// The image API every screen uses. `ImagePipeline` is the real one; tests
/// and previews can substitute their own.
///
/// `targetSize` is in **pixels** (points × display scale). A `nil` target,
/// or a dimension that is 0 or infinite, leaves that dimension unconstrained.
/// Images are never upscaled.
public protocol ImageLoading: Sendable {
    /// Fetches (with the server's auth), caches, and downsamples an image.
    /// Requests for the same URL share one download.
    func load(_ url: URL, server: MangaServer, targetSize: CGSize?, scaling: ImageScaling) async throws -> LoadedImage

    /// A memory-cache hit for exactly this request, without any I/O. Lets
    /// views show a cached image on their first frame.
    func cachedImage(for url: URL, targetSize: CGSize?, scaling: ImageScaling) -> LoadedImage?

    /// Starts downloading in the background. When `targetSize` is given the
    /// images are also decoded into the memory cache. `onPixelSize` is called
    /// (on an arbitrary thread) with each image's original size.
    func prefetch(_ urls: [URL], server: MangaServer, targetSize: CGSize?, onPixelSize: (@Sendable (URL, PageSize) -> Void)?)

    /// Stops prefetches that haven't finished. Doesn't affect `load` calls.
    func cancelPrefetch(_ urls: [URL])

    /// The original pixel size, if this URL has been downloaded before.
    func cachedPixelSize(for url: URL) -> PageSize?
}

public extension ImageLoading {
    func image(for url: URL, server: MangaServer, targetSize: CGSize?) async throws -> PlatformImage {
        try await load(url, server: server, targetSize: targetSize, scaling: .fit).image
    }

    func load(_ url: URL, server: MangaServer, targetSize: CGSize?) async throws -> LoadedImage {
        try await load(url, server: server, targetSize: targetSize, scaling: .fit)
    }

    func prefetch(_ urls: [URL], server: MangaServer) {
        prefetch(urls, server: server, targetSize: nil, onPixelSize: nil)
    }
}
