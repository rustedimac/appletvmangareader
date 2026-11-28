import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// EPUB, PDF and plain-text books that a server only offers as a whole file
/// (OPDS catalogs, Calibre). Each is downloaded once into its own folder in
/// `LocalArchiveCache`'s directory and read from there:
///
/// - EPUB: unzipped; `EPUBPackage` reads it for the book reader, or as
///   pages when every section is one picture.
/// - PDF: kept as `book.pdf`. Page URLs point at `p0000.jpg`… files that
///   don't exist yet; `URLSessionTransport` asks `LocalPDFRenderer` to draw a
///   page the first time it's read (`CGPDFDocument`, since tvOS has no
///   PDFKit), and the image cache keeps it from then on.
/// - Text: kept as `book.txt`, read as one section.
extension LocalArchiveCache {
    /// The unpacked EPUB for the file at `request`.
    public func epub(for request: URLRequest, transport: HTTPTransport) async throws -> EPUBPackage {
        let folder = try await folder(for: request, kind: "epub", transport: transport) { data, staging in
            try Self.unzipAll(data, into: staging)
        }
        if let known = packages[folder.path] { return known }
        let package = try EPUBPackage(folder: folder)
        if packages.count > 8 { packages.removeAll() }
        packages[folder.path] = package
        return package
    }

    /// Pages of the PDF at `request`, with sizes, drawn on first read.
    public func pdfPages(for request: URLRequest, transport: HTTPTransport) async throws -> [PageDescriptor] {
        let folder = try await folder(for: request, kind: "pdf", transport: transport) { data, staging in
            guard data.starts(with: Array("%PDF".utf8)) || data.prefix(1024).range(of: Data("%PDF".utf8)) != nil else {
                throw MangaError.decoding("The file isn't a PDF.")
            }
            try data.write(to: staging.appendingPathComponent(LocalPDFRenderer.fileName))
        }
        let sizes = try LocalPDFRenderer.pageSizes(in: folder)
        guard !sizes.isEmpty else { throw MangaError.decoding("The PDF has no pages.") }
        return sizes.enumerated().map { index, size in
            PageDescriptor(index: index, url: LocalPDFRenderer.pageURL(folder: folder, index: index), size: size)
        }
    }

    /// The text of the plain-text book at `request`.
    public func text(for request: URLRequest, transport: HTTPTransport) async throws -> String {
        let folder = try await folder(for: request, kind: "txt", transport: transport) { data, staging in
            try data.write(to: staging.appendingPathComponent("book.txt"))
        }
        let data = FileManager.default.contents(atPath: folder.appendingPathComponent("book.txt").path) ?? Data()
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Downloads `request` once into its own folder, built by `prepare` in
    /// a staging folder and moved into place when complete.
    func folder(for request: URLRequest, kind: String, transport: HTTPTransport,
                prepare: @escaping @Sendable (Data, URL) throws -> Void) async throws -> URL {
        guard let url = request.url else { throw MangaError.invalidURL("") }
        let key = Self.key(for: url) + "-" + kind
        let folder = directory.appendingPathComponent(key, isDirectory: true)
        let marker = folder.appendingPathComponent(".complete")
        if FileManager.default.fileExists(atPath: marker.path) {
            touch(folder)
            return folder
        }
        if let running = inFlightFolders[key] { return try await running.value }
        let task = Task { () throws -> URL in
            let (data, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300: break
            case 401, 403: throw MangaError.unauthorized
            case 404: throw MangaError.notFound
            default: throw MangaError.http(status: response.statusCode, body: "")
            }
            guard data.count <= Self.maxArchiveBytes else {
                throw MangaError.decoding("This book is too big to open here.")
            }
            let fm = FileManager.default
            let staging = folder.deletingLastPathComponent()
                .appendingPathComponent(folder.lastPathComponent + ".partial-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            do {
                try prepare(data, staging)
                try Data().write(to: staging.appendingPathComponent(".complete"))
                try? fm.removeItem(at: folder)
                try fm.moveItem(at: staging, to: folder)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
            return folder
        }
        inFlightFolders[key] = task
        defer { inFlightFolders[key] = nil }
        let result = try await task.value
        trim(keeping: result)
        return result
    }

    /// Writes every file in the ZIP under `folder`, keeping its paths.
    /// Entries that would land outside the folder are skipped.
    static func unzipAll(_ data: Data, into folder: URL) throws {
        let archive = try ZipArchive(data: data)
        let fm = FileManager.default
        let root = folder.standardizedFileURL.path
        for entry in archive.entries where !entry.isDirectory {
            let parts = entry.path.split(separator: "/").map(String.init)
            guard !parts.isEmpty, !entry.path.hasPrefix("/"), !parts.contains(".."), !parts.contains("__MACOSX") else { continue }
            let target = parts.reduce(folder) { $0.appendingPathComponent($1) }.standardizedFileURL
            guard target.path.hasPrefix(root + "/") else { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try archive.extract(entry).write(to: target)
        }
    }
}

/// Draws PDF pages kept by `LocalArchiveCache.pdfPages` into JPEG files.
public enum LocalPDFRenderer {
    static let fileName = "book.pdf"
    /// Pages are drawn so their longer side is about this many pixels:
    /// sharp on a 4K TV and an iPad, without wasting memory.
    static let longSide: Double = 2400

    static func pageURL(folder: URL, index: Int) -> URL {
        folder.appendingPathComponent(String(format: "p%04d.jpg", index))
    }

    /// The index of a page URL made by `pageURL`, when its folder holds a PDF.
    static func pageIndex(_ url: URL) -> Int? {
        let name = url.lastPathComponent
        guard name.hasPrefix("p"), name.hasSuffix(".jpg"), name.count == 9,
              let index = Int(name.dropFirst().dropLast(4)) else { return nil }
        let pdf = url.deletingLastPathComponent().appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: pdf.path) ? index : nil
    }

    /// For `URLSessionTransport`: the JPEG for a not-yet-drawn page URL,
    /// drawn and saved now. Nil when the URL isn't a PDF page.
    public static func renderedPage(at url: URL) -> Data? {
        guard url.isFileURL, let index = pageIndex(url) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let data = FileManager.default.contents(atPath: url.path) { return data }
        guard let data = render(folder: url.deletingLastPathComponent(), index: index) else { return nil }
        try? data.write(to: url, options: .atomic)
        return data
    }

    /// One page at a time: CoreGraphics PDF documents aren't safe to draw
    /// from several threads, and pages are drawn as they're needed anyway.
    private static let lock = NSLock()

    #if canImport(CoreGraphics) && canImport(ImageIO)
    static func document(in folder: URL) -> CGPDFDocument? {
        CGPDFDocument(folder.appendingPathComponent(fileName) as CFURL)
    }

    static func pageSizes(in folder: URL) throws -> [PageSize] {
        guard let doc = document(in: folder) else { throw MangaError.decoding("The PDF couldn't be opened.") }
        guard !doc.isEncrypted || doc.unlockWithPassword("") else {
            throw MangaError.decoding("The PDF is password protected.")
        }
        return (0..<doc.numberOfPages).map { i in
            guard let page = doc.page(at: i + 1) else { return PageSize(width: 1, height: 1.414) }
            let box = page.getBoxRect(.cropBox)
            let rotated = abs(page.rotationAngle) % 180 == 90
            return PageSize(width: Double(rotated ? box.height : box.width), height: Double(rotated ? box.width : box.height))
        }
    }

    static func render(folder: URL, index: Int) -> Data? {
        guard let doc = document(in: folder), !doc.isEncrypted || doc.unlockWithPassword(""),
              let page = doc.page(at: index + 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        let w = Double(rotated ? box.height : box.width), h = Double(rotated ? box.width : box.height)
        guard w > 0, h > 0 else { return nil }
        let scale = longSide / max(w, h)
        let width = Int((w * scale).rounded()), height = Int((h * scale).rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
    #else
    static func pageSizes(in folder: URL) throws -> [PageSize] {
        throw MangaError.decoding("PDFs can't be opened on this platform.")
    }

    static func render(folder: URL, index: Int) -> Data? { nil }
    #endif
}
