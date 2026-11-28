import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Downloads a comic archive (CBZ/ZIP) that a server only offers as a whole
/// file, unpacks its pages into Caches, and hands back `file://` page URLs
/// the image pipeline can read (`URLSessionTransport` serves file URLs).
/// EPUBs and PDFs are kept the same way (`LocalBookFiles.swift`).
///
/// tvOS may purge Caches at any time; a missing book is simply downloaded
/// again. The oldest books are removed once the folder passes `byteLimit`.
public actor LocalArchiveCache {
    public static let shared = LocalArchiveCache()

    let directory: URL
    let byteLimit: Int
    /// Archives bigger than this aren't downloaded (they'd sit in memory).
    public static let maxArchiveBytes = 600 * 1024 * 1024

    private var inFlight: [String: Task<[URL], Error>] = [:]
    /// Downloads being unpacked into a folder (EPUB, PDF), by key.
    var inFlightFolders: [String: Task<URL, Error>] = [:]
    /// Parsed EPUBs by folder path, so turning sections doesn't re-read
    /// the package each time.
    var packages: [String: EPUBPackage] = [:]

    public init(directory: URL? = nil, byteLimit: Int = 1_500 * 1024 * 1024) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalArchives", isDirectory: true)
        self.directory = base
        self.byteLimit = byteLimit
    }

    /// Page files for the archive at `url`, downloading it if needed.
    public func pages(for request: URLRequest, transport: HTTPTransport) async throws -> [URL] {
        guard let url = request.url else { throw MangaError.invalidURL("") }
        let key = Self.key(for: url)
        let folder = directory.appendingPathComponent(key, isDirectory: true)
        if let cached = Self.cachedPages(in: folder) {
            touch(folder)
            return cached
        }
        if let running = inFlight[key] { return try await running.value }
        let task = Task { () throws -> [URL] in
            let (data, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300: break
            case 401, 403: throw MangaError.unauthorized
            case 404: throw MangaError.notFound
            default: throw MangaError.http(status: response.statusCode, body: "")
            }
            guard data.count <= Self.maxArchiveBytes else {
                throw MangaError.decoding("This book is too big to open on Apple TV.")
            }
            return try Self.unpack(data, into: folder)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let pages = try await task.value
        trim(keeping: folder)
        return pages
    }

    /// Writes every image in the archive to `folder` as 0000.ext, 0001.ext…
    static func unpack(_ data: Data, into folder: URL) throws -> [URL] {
        let archive = try ZipArchive(data: data)
        let images = archive.imageEntries
        guard !images.isEmpty else { throw MangaError.decoding("The archive has no pages.") }
        let fm = FileManager.default
        let staging = folder.deletingLastPathComponent()
            .appendingPathComponent(folder.lastPathComponent + ".partial-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for (index, entry) in images.enumerated() {
                let ext = (entry.path as NSString).pathExtension.lowercased()
                let file = staging.appendingPathComponent(String(format: "%04d.%@", index, ext))
                try archive.extract(entry).write(to: file)
            }
            try? fm.removeItem(at: folder)
            try fm.moveItem(at: staging, to: folder)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        return cachedPages(in: folder) ?? []
    }

    static func cachedPages(in folder: URL) -> [URL]? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              !files.isEmpty else { return nil }
        return files.filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func touch(_ folder: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: folder.path)
    }

    /// Removes the least recently opened books until under the limit.
    func trim(keeping current: URL) {
        let fm = FileManager.default
        guard let books = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        func size(_ folder: URL) -> Int {
            // Unpacked EPUBs have subfolders.
            guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var total = 0
            for case let file as URL in walker {
                total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
            return total
        }
        var entries = books.map { book -> (URL, Date, Int) in
            let date = (try? book.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (book, date, size(book))
        }.sorted { $0.1 < $1.1 }
        var total = entries.reduce(0) { $0 + $1.2 }
        while total > byteLimit, let oldest = entries.first {
            entries.removeFirst()
            guard oldest.0.standardizedFileURL != current.standardizedFileURL else { continue }
            try? fm.removeItem(at: oldest.0)
            total -= oldest.2
        }
    }

    /// A file-system-safe key for a URL (credentials are never in it).
    static func key(for url: URL) -> String {
        let text = url.absoluteString
        #if canImport(CryptoKit)
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        // FNV-1a, for Linux test runs.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
        #endif
    }
}
