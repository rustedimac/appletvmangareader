import Foundation
import CoreGraphics
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Loads cover and page images for every screen. Use `ImagePipeline.shared`
/// (the SwiftUI environment's `imagePipeline` defaults to it).
public final class ImagePipeline: ImageLoading, @unchecked Sendable {
    public static let shared = ImagePipeline()

    let transport: HTTPTransport
    private let memory = NSCache<NSString, CachedImage>()
    private let lock = NSLock()
    private var pixelSizes: [String: PageSize] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    /// - Parameter memoryLimit: bytes of decoded images kept in memory.
    public init(transport: HTTPTransport = URLSessionTransport(session: ImagePipeline.makeSession()),
                memoryLimit: Int = 256 * 1024 * 1024) {
        self.transport = transport
        memory.totalCostLimit = memoryLimit
    }

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
        let data = try await fetch(url, server: server)
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
            let running = prefetchTasks[key] != nil
            lock.unlock()
            if running { continue }
            let task = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                defer { self.finishPrefetch(key) }
                if let size = self.cachedPixelSize(for: url), targetSize == nil {
                    onPixelSize?(url, size)
                    return
                }
                guard let loaded = try? await self.load(url, server: server, targetSize: targetSize, scaling: .fit) else { return }
                onPixelSize?(url, loaded.pixelSize)
            }
            lock.lock()
            prefetchTasks[key] = task
            lock.unlock()
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

    /// Drops decoded images (e.g. on a memory warning). Sizes are kept.
    public func clearMemory() {
        memory.removeAllObjects()
    }

    // MARK: Internals

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
        lock.lock()
        pixelSizes[Self.cacheKey(url)] = image.pixelSize
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
