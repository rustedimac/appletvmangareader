import Foundation
import CoreGraphics
import MangaCore

/// Detected page margins by image URL, so each page is analyzed once per
/// app run however often it is shown, re-decoded or preloaded. Insets are
/// fractions, so they're the same at any decode size.
final class PageCropCache: @unchecked Sendable {
    static let shared = PageCropCache()

    private let lock = NSLock()
    private var entries: [URL: CropInsets] = [:]
    private var order: [URL] = []
    private let limit = 2000

    func cached(_ url: URL) -> CropInsets? {
        lock.lock(); defer { lock.unlock() }
        return entries[url]
    }

    /// The cached insets, or detects them off the main thread.
    func crop(for url: URL, image: CGImage) async -> CropInsets {
        if let hit = cached(url) { return hit }
        let insets = await Task.detached(priority: .userInitiated) {
            BorderCropDetector.detect(in: image)
        }.value
        store(insets, for: url)
        return insets
    }

    private func store(_ insets: CropInsets, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        if entries.updateValue(insets, forKey: url) == nil {
            order.append(url)
            if order.count > limit {
                let drop = order.prefix(order.count - limit)
                for u in drop { entries[u] = nil }
                order.removeFirst(drop.count)
            }
        }
    }
}
