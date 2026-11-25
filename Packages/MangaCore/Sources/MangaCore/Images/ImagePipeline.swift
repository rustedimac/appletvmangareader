import Foundation
import CoreGraphics
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Loads cover and page images for every screen. Use `ImagePipeline.shared`
/// (the SwiftUI environment's `imagePipeline` defaults to it).
public final class ImagePipeline: ImageLoading, @unchecked Sendable {
    public static let shared = ImagePipeline()

    let transport: HTTPTransport
    let disk: DiskImageCache?
    private let memory = NSCache<NSString, CachedImage>()
    private let coalescer = FetchCoalescer()
    private let limiter: DownloadLimiter
    /// Per-attempt timeout and automatic retries for downloads.
    let retryPolicy: RetryPolicy
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let lock = NSLock()
    private var pixelSizes: [String: PageSize] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private var memoryWarningObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - memoryLimit: bytes of decoded images kept in memory.
    ///   - diskDirectory: where encoded images are cached; `nil` disables the disk cache.
    ///   - diskLimit: bytes kept on disk before the oldest files are removed.
    ///   - maxConcurrentDownloads: parallel downloads across all servers.
    ///   - retryPolicy: time limit per download attempt and automatic
    ///     retries for timeouts, dropped connections and HTTP 5xx.
    ///   - sleep: waits between retries (tests pass one that returns at once).
    public init(transport: HTTPTransport = URLSessionTransport(session: ImagePipeline.makeSession()),
                memoryLimit: Int = 256 * 1024 * 1024,
                diskDirectory: URL? = ImagePipeline.defaultDiskDirectory,
                diskLimit: Int = 512 * 1024 * 1024,
                maxConcurrentDownloads: Int = 6,
                retryPolicy: RetryPolicy = .images,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = RetryPolicy.taskSleep) {
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.sleep = sleep
        self.disk = diskDirectory.map { DiskImageCache(directory: $0, limit: diskLimit) }
        self.limiter = DownloadLimiter(limit: maxConcurrentDownloads)
        memory.totalCostLimit = memoryLimit
        #if canImport(UIKit) && !os(watchOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.clearMemory() }
        #endif
    }

    deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    /// `Library/Caches/ImagePipeline`.
    public static var defaultDiskDirectory: URL { DiskImageCache.defaultDirectory() }

    /// A session without URLCache (the pipeline caches itself) that allows a
    /// few parallel downloads per server.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }

    // MARK: ImageLoading

    public func load(_ url: URL, server: MangaServer, targetSize: CGSize?, scaling: ImageScaling) async throws -> LoadedImage {
        let target = Self.bucketed(targetSize)
        let key = Self.memoryKey(url, targetSize: target, scaling: scaling)
        if let hit = memory.object(forKey: key as NSString) { return hit.value }
        let data = try await data(for: url, server: server, high: true)
        try Task.checkCancellation()
        let image = try ImageDecoder.decode(data, targetSize: target, scaling: scaling)
        store(image, key: key, url: url)
        return image
    }

    public func cachedImage(for url: URL, targetSize: CGSize?, scaling: ImageScaling) -> LoadedImage? {
        memory.object(forKey: Self.memoryKey(url, targetSize: Self.bucketed(targetSize), scaling: scaling) as NSString)?.value
    }

    public func prefetch(_ urls: [URL], server: MangaServer, targetSize: CGSize?, onPixelSize: (@Sendable (URL, PageSize) -> Void)?) {
        for url in urls {
            let key = Self.cacheKey(url)
            lock.lock()
            defer { lock.unlock() }
            if prefetchTasks[key] != nil { continue }
            // Created under the lock so a fast finish can't run before the
            // task is registered.
            prefetchTasks[key] = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                defer { self.finishPrefetch(key) }
                if let targetSize {
                    let target = Self.bucketed(targetSize)
                    let memKey = Self.memoryKey(url, targetSize: target, scaling: .fit)
                    if let hit = self.memory.object(forKey: memKey as NSString) {
                        onPixelSize?(url, hit.value.pixelSize)
                        return
                    }
                    guard let data = try? await self.data(for: url, server: server, high: false),
                          !Task.isCancelled,
                          let image = try? ImageDecoder.decode(data, targetSize: target, scaling: .fit) else { return }
                    self.store(image, key: memKey, url: url)
                    onPixelSize?(url, image.pixelSize)
                } else {
                    if let size = self.cachedPixelSize(for: url) {
                        onPixelSize?(url, size)
                        return
                    }
                    guard let data = try? await self.data(for: url, server: server, high: false),
                          let size = ImageDecoder.pixelSize(of: data) else { return }
                    self.recordSize(size, url: url)
                    onPixelSize?(url, size)
                }
            }
        }
    }

    public func cancelPrefetch(_ urls: [URL]) {
        lock.lock()
        let tasks = urls.compactMap { prefetchTasks.removeValue(forKey: Self.cacheKey($0)) }
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    public func cachedPixelSize(for url: URL) -> PageSize? {
        lock.lock(); defer { lock.unlock() }
        return pixelSizes[Self.cacheKey(url)]
    }

    /// Drops decoded images (done automatically on a memory warning).
    /// Sizes and the disk cache are kept.
    public func clearMemory() {
        memory.removeAllObjects()
    }

    /// Empties the memory and disk caches (Settings → "Clear image cache").
    public func clearAll() {
        memory.removeAllObjects()
        disk?.removeAll()
    }

    /// Bytes in the disk cache.
    public var diskUsage: Int { disk?.size ?? 0 }

    // MARK: Internals

    /// Encoded bytes from disk, or one shared, rate-limited download.
    func data(for url: URL, server: MangaServer, high: Bool) async throws -> Data {
        let key = Self.cacheKey(url)
        if let cached = disk?.data(for: key) { return cached }
        if high { await limiter.promote(key) }
        return try await coalescer.data(for: key) { [self] in
            if let cached = disk?.data(for: key) { return cached }
            // Each attempt holds a download slot only while it runs, and the
            // time limit starts once it has one, so waiting behind other
            // downloads never counts as a timeout.
            let data = try await retryPolicy.run(timingEachAttempt: false, sleep: sleep) { [self] _ in
                await limiter.acquire(key: key, high: high)
                let result: Result<Data, Error>
                do {
                    try Task.checkCancellation()
                    let policy = retryPolicy
                    result = .success(try await RetryPolicy.withTimeout(policy.attemptTimeout) { [self] in
                        try await fetch(url, server: server)
                    })
                } catch {
                    result = .failure(error)
                }
                await limiter.release()
                return try result.get()
            }
            // Only keep bytes ImageIO can read, so a login page or error
            // body never gets cached as an image.
            if let size = ImageDecoder.pixelSize(of: data) {
                disk?.store(data, for: key)
                recordSize(size, url: url)
            }
            return data
        }
    }

    func fetch(_ url: URL, server: MangaServer) async throws -> Data {
        let (data, response) = try await transport.send(server.imageRequest(url))
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw MangaError.unauthorized
        case 404: throw MangaError.notFound
        default: throw MangaError.http(status: response.statusCode, body: String(decoding: data.prefix(200), as: UTF8.self))
        }
    }

    private func store(_ image: LoadedImage, key: String, url: URL) {
        let cost = image.cgImage.bytesPerRow * image.cgImage.height
        memory.setObject(CachedImage(image), forKey: key as NSString, cost: cost)
        recordSize(image.pixelSize, url: url)
    }

    private func recordSize(_ size: PageSize, url: URL) {
        lock.lock()
        pixelSizes[Self.cacheKey(url)] = size
        lock.unlock()
    }

    private func finishPrefetch(_ key: String) {
        lock.lock()
        prefetchTasks[key] = nil
        lock.unlock()
    }

    /// The URL without Kavita's `apiKey`, so the cache survives key changes
    /// and different profiles share entries.
    static func cacheKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.contains(where: { $0.name.lowercased() == "apikey" }) else {
            return url.absoluteString
        }
        let kept = items.filter { $0.name.lowercased() != "apikey" }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url?.absoluteString ?? url.absoluteString
    }

    /// Target sizes are rounded up to a multiple of 64 px so small layout
    /// changes reuse the cached decode. Unconstrained dimensions become 0.
    static func bucketed(_ size: CGSize?) -> CGSize? {
        guard let size else { return nil }
        func bucket(_ v: CGFloat) -> CGFloat {
            guard v > 0, v.isFinite else { return 0 }
            return (v / 64).rounded(.up) * 64
        }
        return CGSize(width: bucket(size.width), height: bucket(size.height))
    }

    static func memoryKey(_ url: URL, targetSize: CGSize?, scaling: ImageScaling) -> String {
        let w = Int(targetSize?.width ?? 0), h = Int(targetSize?.height ?? 0)
        return "\(cacheKey(url))|\(w)x\(h)|\(scaling == .fit ? "fit" : "fill")"
    }
}

final class CachedImage {
    let value: LoadedImage
    init(_ value: LoadedImage) { self.value = value }
}
