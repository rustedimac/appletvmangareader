import UIKit
import ImageIO
import MangaCore

/// A decoded page and the pixel size of the original image.
struct LoadedPage: @unchecked Sendable {
    let image: UIImage
    let pixelSize: PageSize
}

/// Loads, downsamples and caches page images for the paged reader, with
/// request coalescing and a preload window. Kept local to the reader so it
/// can be swapped for the shared image pipeline once that lands.
@MainActor
final class PageImageLoader {
    private let server: MangaServer
    /// Longest side, in pixels, images are decoded to. A page never needs
    /// more than the screen's height in pixels.
    private let maxPixelSize: Int
    private let cache = NSCache<NSURL, CachedPage>()
    private var inFlight: [URL: Task<LoadedPage, Error>] = [:]

    private final class CachedPage {
        let page: LoadedPage
        init(_ page: LoadedPage) { self.page = page }
    }

    /// Per-attempt timeout and automatic retries for downloads.
    private let retryPolicy: RetryPolicy

    init(server: MangaServer, maxPixelSize: Int = 2160,
         retryPolicy: RetryPolicy = ReaderDemo.isEnabled ? ReaderDemo.retryPolicy : .images) {
        self.server = server
        self.retryPolicy = retryPolicy
        self.maxPixelSize = maxPixelSize
        cache.countLimit = 14
    }

    func cached(_ url: URL) -> LoadedPage? {
        cache.object(forKey: url as NSURL)?.page
    }

    func load(_ url: URL) async throws -> LoadedPage {
        if let hit = cached(url) { return hit }
        if let task = inFlight[url] { return try await task.value }
        let request = server.imageRequest(url)
        let maxPixelSize = self.maxPixelSize
        let policy = retryPolicy
        let task = Task<LoadedPage, Error> {
            // Timeouts, dropped connections and 5xx are retried before the
            // page shows as failed; Select then retries it by hand.
            let data: Data = try await policy.run { _ in
                if url.scheme == DemoPageRenderer.scheme {
                    try await DemoPageFaults.shared.apply(to: url)
                    return DemoPageRenderer.pngData(for: url)
                }
                let (body, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw MangaError.http(status: http.statusCode, body: "")
                }
                return body
            }
            return try await Task.detached(priority: .userInitiated) {
                try PageImageLoader.decode(data, maxPixelSize: maxPixelSize)
            }.value
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let page = try await task.value
        cache.setObject(CachedPage(page), forKey: url as NSURL)
        return page
    }

    /// Starts loading pages near the current spread and cancels loads that
    /// fell out of the window. `urls` is nearest first.
    func preload(_ urls: [URL], onLoaded: @escaping (URL, LoadedPage) -> Void) {
        let keep = Set(urls)
        for (url, task) in inFlight where !keep.contains(url) { task.cancel() }
        for url in urls where cached(url) == nil && inFlight[url] == nil {
            Task {
                if let page = try? await load(url) { onLoaded(url, page) }
            }
        }
    }

    nonisolated private static func decode(_ data: Data, maxPixelSize: Int) throws -> LoadedPage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw MangaError.decoding("Not an image")
        }
        var pixelSize: PageSize?
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Double,
           let h = props[kCGImagePropertyPixelHeight] as? Double {
            pixelSize = PageSize(width: w, height: h)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw MangaError.decoding("Couldn't decode image")
        }
        let size = pixelSize ?? PageSize(width: Double(cg.width), height: Double(cg.height))
        return LoadedPage(image: UIImage(cgImage: cg), pixelSize: size)
    }
}
