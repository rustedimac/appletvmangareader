import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// EPUB reading through Kavita's book API (`BookController`). Kavita
/// serves an EPUB one spine item at a time as scoped HTML; the app parses
/// that into blocks and lays it out itself, because tvOS has no WebKit.
/// PDFs don't come through here: Kavita renders their pages to images
/// (`extractPdf=true`) and they open in the image readers.
extension KavitaClient: BookProviding {
    public func bookManifest(for chapter: Chapter) async throws -> BookManifest {
        try await withAuth { client in
            let info: KavitaBookInfoDTO = try await client.get("api/Book/\(chapter.id)/book-info")
            // The table of contents is a nice extra; a book without one
            // still opens.
            let items: [KavitaBookChapterItemDTO] = (try? await client.get("api/Book/\(chapter.id)/chapters")) ?? []
            let title = [info.bookTitle, info.chapterTitle].compactMap { $0 }.first { !$0.isEmpty } ?? chapter.title
            let count = max(info.pages ?? 0, chapter.pageCount)
            return BookManifest(title: title, sectionCount: count, toc: Self.tocEntries(items, sectionCount: count))
        }
    }

    public func bookSection(_ index: Int, of chapter: Chapter) async throws -> BookSection {
        let data: Data = try await withAuth { client in
            try await client.send(try client.request("GET", "api/Book/\(chapter.id)/book-page",
                                                     query: ["page": String(index)]))
        }
        let html = Self.decodeBookPage(data)
        let parser = HTMLBookParser(resolveURL: { [config] src in Self.resolveResource(src, baseURL: config.baseURL) })
        return parser.parse(html, section: index)
    }

    static func tocEntries(_ items: [KavitaBookChapterItemDTO], sectionCount: Int) -> [BookTOCEntry] {
        items.map { item in
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let section = min(max(0, item.page ?? 0), max(0, sectionCount - 1))
            return BookTOCEntry(title: (title?.isEmpty == false ? title! : "Section \(section + 1)"),
                                section: section,
                                anchor: item.part.flatMap { $0.isEmpty ? nil : $0 },
                                children: tocEntries(item.children ?? [], sectionCount: sectionCount))
        }
    }

    /// `book-page` is an `ActionResult<string>`: plain text, or a JSON
    /// string when the request asks for JSON (ours do).
    static func decodeBookPage(_ data: Data) -> String {
        let firstByte = data.first { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }
        if firstByte == UInt8(ascii: "\""), let string = try? JSONDecoder().decode(String.self, from: data) {
            return string
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Kavita rewrites EPUB image sources to protocol-relative URLs on the
    /// host the request came in on (`//host/api/book/12/book-resources?...`).
    /// Send them to the server address the app was given instead, so they
    /// work behind reverse proxies and with `.local` names alike.
    static func resolveResource(_ src: String, baseURL: URL) -> URL? {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            guard let parsed = URLComponents(string: "http:" + trimmed),
                  var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
            components.percentEncodedPath = parsed.percentEncodedPath
            components.percentEncodedQuery = parsed.percentEncodedQuery
            components.fragment = nil
            return components.url
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            return scheme == "http" || scheme == "https" ? url : nil
        }
        var base = baseURL.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        return URL(string: trimmed, relativeTo: URL(string: base))?.absoluteURL
    }
}
