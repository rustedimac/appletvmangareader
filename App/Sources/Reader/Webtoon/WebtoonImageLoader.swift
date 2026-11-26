import UIKit
import ImageIO
import MangaCore

/// A decoded page ready for the strip: one or more tiles, each with the
/// rows of the page it covers.
struct WebtoonPageImage: @unchecked Sendable {
    let pixelSize: PageSize
    let plan: WebtoonTilePlan
    let tiles: [CGImage]
    /// Display size (device pixels) the plan was made for.
    let displayWidth: Int
    let displayHeight: Int

    var cost: Int { plan.decodeWidth * plan.decodeHeight * 4 }
}

/// Downloads, sizes and decodes webtoon pages.
///
/// Webtoon pages need different handling from the paged reader's: they're
/// decoded to the column's width (not the screen's height, which would make
/// a tall strip blurry), and very tall strips are split into tiles that fit
/// in a GPU texture. Downloads are coalesced and kept in a memory cache so a
/// size probe ahead of the reader doesn't cost a second download when the
/// page scrolls into view. Kept in the webtoon folder; the fetch step can
/// move to the shared image pipeline once it lands.
@MainActor
final class WebtoonImageLoader {
    private let server: MangaServer
    private let dataCache = NSCache<NSURL, NSData>()
    private let imageCache = NSCache<NSString, ImageBox>()
    private var pixelSizes: [URL: PageSize] = [:]
    private var downloads: [URL: Task<Data, Error>] = [:]
    private var prefetches: [URL: Task<Void, Never>] = [:]
    /// When a size prefetch last failed, so scrolling doesn't restart it on
    /// every frame while the server is down.
    private var prefetchFailures: [URL: Date] = [:]

    private final class ImageBox {
        let image: WebtoonPageImage
        init(_ image: WebtoonPageImage) { self.image = image }
    }

    /// Per-attempt timeout and automatic retries for downloads.
    private let retryPolicy: RetryPolicy

    init(server: MangaServer, retryPolicy: RetryPolicy = .images) {
        self.server = server
        self.retryPolicy = retryPolicy
        dataCache.totalCostLimit = 96 << 20
        imageCache.totalCostLimit = 160 << 20
    }

    func knownPixelSize(_ url: URL) -> PageSize? { pixelSizes[url] }

    func cachedImage(_ url: URL, displayWidth: Int) -> WebtoonPageImage? {
        imageCache.object(forKey: Self.key(url, displayWidth))?.image
    }

    /// The page decoded for a column `displayWidth` device pixels wide.
    func image(_ url: URL, displayWidth: Int) async throws -> WebtoonPageImage {
        if let hit = cachedImage(url, displayWidth: displayWidth) { return hit }
        let data = try await self.data(url)
        let size = try await pixelSize(of: data, url: url)
        let height = WebtoonGeometry.pageHeightPixels(size, columnPixels: displayWidth, estimate: 0)
        let plan = WebtoonTilePlan(source: size, displayWidth: displayWidth, displayHeight: height)
        try Task.checkCancellation()
        let tiles = try await Task.detached(priority: .userInitiated) {
            try WebtoonImageLoader.decode(data, plan: plan)
        }.value
        let image = WebtoonPageImage(pixelSize: size, plan: plan, tiles: tiles,
                                     displayWidth: displayWidth, displayHeight: height)
        imageCache.setObject(ImageBox(image), forKey: Self.key(url, displayWidth), cost: image.cost)
        return image
    }

    /// The original pixel size, downloading the page if needed.
    func pixelSize(_ url: URL) async throws -> PageSize {
        if let known = pixelSizes[url] { return known }
        let data = try await self.data(url)
        return try await pixelSize(of: data, url: url)
    }

    /// Downloads pages ahead of the reader to learn their sizes, so their
    /// heights are right before they scroll into view. Cancels earlier
    /// prefetches that aren't in `urls` any more.
    func prefetchSizes(_ urls: [URL], onSize: @escaping (URL, PageSize) -> Void) {
        let keep = Set(urls)
        for (url, task) in prefetches where !keep.contains(url) {
            task.cancel()
            prefetches[url] = nil
        }
        let now = Date()
        for url in urls where pixelSizes[url] == nil && prefetches[url] == nil {
            if let failed = prefetchFailures[url], now.timeIntervalSince(failed) < 15 { continue }
            prefetches[url] = Task { [weak self] in
                defer { self?.prefetches[url] = nil }
                guard let self else { return }
                do {
                    let size = try await self.pixelSize(url)
                    guard !Task.isCancelled else { return }
                    self.prefetchFailures[url] = nil
                    onSize(url, size)
                } catch {
                    if !Task.isCancelled { self.prefetchFailures[url] = Date() }
                }
            }
        }
    }

    func cancelAll() {
        for task in prefetches.values { task.cancel() }
        prefetches.removeAll()
    }

    // MARK: Internals

    private func data(_ url: URL) async throws -> Data {
        if let hit = dataCache.object(forKey: url as NSURL) { return hit as Data }
        if let running = downloads[url] { return try await running.value }
        let request = server.imageRequest(url)
        let policy = retryPolicy
        // Timeouts, dropped connections and 5xx are retried before the page
        // shows as failed; the user can then retry it by hand.
        let task = Task<Data, Error>.detached(priority: .userInitiated) {
            try await policy.run { _ in
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
        }
        downloads[url] = task
        defer { downloads[url] = nil }
        let data = try await task.value
        dataCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }

    private func pixelSize(of data: Data, url: URL) async throws -> PageSize {
        if let known = pixelSizes[url] { return known }
        let size = try await Task.detached(priority: .userInitiated) {
            try WebtoonImageLoader.readSize(data)
        }.value
        pixelSizes[url] = size
        return size
    }

    private static func key(_ url: URL, _ width: Int) -> NSString {
        "\(width)|\(url.absoluteString)" as NSString
    }

    nonisolated static func readSize(_ data: Data) throws -> PageSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0 else {
            throw MangaError.decoding("Not an image")
        }
        // EXIF orientations 5–8 are rotated a quarter turn.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? PageSize(width: h, height: w) : PageSize(width: w, height: h)
    }

    /// Decodes `data` as `plan` says: downsampled with ImageIO, redrawn to
    /// the exact plan size when the page is split, then cut into tiles
    /// (crops share the decoded bitmap).
    nonisolated static func decode(_ data: Data, plan: WebtoonTilePlan) throws -> [CGImage] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw MangaError.decoding("Not an image")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(plan.decodeWidth, plan.decodeHeight),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw MangaError.decoding("Couldn't decode image")
        }
        guard plan.requiresExactSize else { return [decoded] }

        let w = plan.decodeWidth, h = plan.decodeHeight
        let exact: CGImage
        if decoded.width == w && decoded.height == h {
            exact = decoded
        } else {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else {
                throw MangaError.decoding("Couldn't allocate image")
            }
            ctx.interpolationQuality = .high
            ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let image = ctx.makeImage() else { throw MangaError.decoding("Couldn't draw image") }
            exact = image
        }
        return try plan.tiles.map { tile in
            guard let crop = exact.cropping(to: CGRect(x: 0, y: tile.sourceY, width: w, height: tile.sourceHeight)) else {
                throw MangaError.decoding("Couldn't split image")
            }
            return crop
        }
    }
}
