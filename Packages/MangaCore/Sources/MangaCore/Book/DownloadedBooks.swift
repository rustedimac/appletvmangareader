import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A server whose books are whole files the app downloads and reads on
/// device (OPDS catalogs, Calibre), as opposed to Kavita, which serves an
/// EPUB section by section. The reader asks these servers up front whether
/// an EPUB is really a picture book, so it opens in the image readers.
public protocol DownloadsBookFiles: BookProviding {}

/// Reads one downloaded book file for `pages(for:)` and `BookProviding`:
/// CBZ as pages, PDF as drawn pages, EPUB and text as sections (or an
/// all-pictures EPUB as pages). Shared by `OPDSClient` and `CalibreClient`.
struct DownloadedBook {
    let request: URLRequest
    let kind: ContentKind
    let archives: LocalArchiveCache
    let transport: HTTPTransport

    func pages() async throws -> [PageDescriptor] {
        switch kind {
        case .comicArchive:
            let urls = try await archives.pages(for: request, transport: transport)
            return urls.enumerated().map { PageDescriptor(index: $0, url: $1) }
        case .pdf:
            return try await archives.pdfPages(for: request, transport: transport)
        case .epub:
            let package = try await archives.epub(for: request, transport: transport)
            guard let images = package.imagePages else {
                throw MangaError.decoding("This EPUB is a text book; it opens in the book reader.")
            }
            return images.enumerated().map { PageDescriptor(index: $0, url: $1) }
        case .text:
            throw MangaError.decoding("This is a text book; it opens in the book reader.")
        case .other:
            throw MangaError.decoding("This book's format isn't supported.")
        }
    }

    func manifest(title: String) async throws -> BookManifest {
        switch kind {
        case .epub:
            var manifest = try await archives.epub(for: request, transport: transport).manifest
            if manifest.title.isEmpty { manifest.title = title }
            return manifest
        case .text:
            let text = try await archives.text(for: request, transport: transport)
            return BookManifest(title: title, sectionCount: Self.textSections(text).count)
        default:
            throw MangaError.decoding("This book opens in the page reader.")
        }
    }

    func section(_ index: Int) async throws -> BookSection {
        switch kind {
        case .epub:
            return try await archives.epub(for: request, transport: transport).section(index)
        case .text:
            let parts = Self.textSections(try await archives.text(for: request, transport: transport))
            guard parts.indices.contains(index) else { throw MangaError.notFound }
            return PlainTextBookParser.parse(parts[index], section: index)
        default:
            throw MangaError.decoding("This book opens in the page reader.")
        }
    }

    /// A long text file split into sections of about `size` characters at
    /// blank lines, so the book reader lays out one part at a time.
    static func textSections(_ text: String, size: Int = 40_000) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var parts: [String] = []
        var current = ""
        for paragraph in normalized.components(separatedBy: "\n\n") {
            if !current.isEmpty, current.count + paragraph.count > size {
                parts.append(current)
                current = ""
            }
            current += current.isEmpty ? paragraph : "\n\n" + paragraph
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parts.isEmpty { parts.append(current) }
        return parts
    }
}
