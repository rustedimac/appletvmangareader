import Foundation
import CryptoKit

/// Encoded image bytes in Caches, trimmed oldest-first past a size limit.
/// tvOS can purge Caches at any time, so every read tolerates a miss.
final class DiskImageCache: @unchecked Sendable {
    let directory: URL
    let limit: Int
    private let queue = DispatchQueue(label: "MangaCore.DiskImageCache")
    private let fm = FileManager.default
    /// Bytes on disk, computed on first use.
    private var totalSize: Int?

    init(directory: URL, limit: Int) {
        self.directory = directory
        self.limit = limit
    }

    static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("ImagePipeline", isDirectory: true)
    }

    /// File name for a key: a hash, so URLs (and anything in them) never
    /// appear on disk.
    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func data(for key: String) -> Data? {
        queue.sync {
            let url = fileURL(key)
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Touch so trimming keeps recently used files.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return data
        }
    }

    func store(_ data: Data, for key: String) {
        queue.async { [self] in
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = fileURL(key)
            // Read the total before writing, or the first scan would count
            // this file twice.
            let before = currentTotal()
            let previous = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            var total = before - previous + data.count
            if total > limit { total = trim(to: limit * 3 / 4) }
            totalSize = total
        }
    }

    func removeAll() {
        queue.sync {
            try? fm.removeItem(at: directory)
            totalSize = 0
        }
    }

    /// Waits for pending writes. For tests.
    func flush() { queue.sync {} }

    var size: Int { queue.sync { currentTotal() } }

    // MARK: Private (on queue)

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: key))
    }

    private func entries() -> [(url: URL, size: Int, date: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
    }

    private func currentTotal() -> Int {
        if let totalSize { return totalSize }
        let total = entries().reduce(0) { $0 + $1.size }
        totalSize = total
        return total
    }

    private func trim(to target: Int) -> Int {
        var all = entries().sorted { $0.date < $1.date }
        var total = all.reduce(0) { $0 + $1.size }
        while total > target, !all.isEmpty {
            let oldest = all.removeFirst()
            try? fm.removeItem(at: oldest.url)
            total -= oldest.size
        }
        return total
    }
}
