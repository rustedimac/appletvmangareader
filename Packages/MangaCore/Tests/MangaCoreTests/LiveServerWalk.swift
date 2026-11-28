import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Shared by the `*LiveTests`: browses a real server through any
/// `MangaServer` and opens the first chapter of each format it finds
/// (pages for images and PDFs, sections for EPUB and text). Read-only:
/// nothing is written to the server.
enum LiveServerWalk {
    @discardableResult
    static func run(_ client: MangaServer, file: StaticString = #filePath, line: UInt = #line) async throws -> Set<String> {
        print("validate:", try await client.validate())
        let categories = try await client.categories()
        print("categories:", categories.map(\.name))
        XCTAssertFalse(categories.isEmpty, "no libraries or categories", file: file, line: line)
        for feed in HomeFeed.allCases {
            print("\(feed):", (try await client.feed(feed, limit: 5)).map(\.title))
        }
        var opened: Set<String> = []
        for category in categories {
            let page = try await client.series(in: category, page: 1, pageSize: 50)
            print("\(category.name):", page.items.map(\.title))
            for series in page.items {
                let detail = try await client.seriesDetail(series.ref.seriesID)
                guard let chapter = detail.chapters.first else { continue }
                let kind = chapter.format?.displayName ?? "Images"
                guard !opened.contains(kind) else { continue }
                if chapter.format?.isText == true, let books = client as? BookProviding {
                    let manifest = try await books.bookManifest(for: chapter)
                    let section = try await books.bookSection(min(1, max(0, manifest.sectionCount - 1)), of: chapter)
                    print("  \(detail.summary.title) [\(kind)]: \(manifest.sectionCount) sections, toc \(manifest.toc.count), "
                          + "\(section.blocks.count) blocks")
                    XCTAssertGreaterThan(manifest.sectionCount, 0, file: file, line: line)
                } else {
                    let pages = try await client.pages(for: chapter)
                    XCTAssertFalse(pages.isEmpty, "\(detail.summary.title) has no pages", file: file, line: line)
                    guard let first = pages.first else { continue }
                    let (data, response) = try await URLSessionTransport().send(client.imageRequest(first.url))
                    print("  \(detail.summary.title) [\(kind)]: \(pages.count) pages, first \(data.count) bytes")
                    XCTAssertEqual(response.statusCode, 200, first.url.absoluteString, file: file, line: line)
                    XCTAssertGreaterThan(data.count, 100, file: file, line: line)
                }
                opened.insert(kind)
            }
            if let cover = page.items.first?.coverURL {
                let (_, response) = try await URLSessionTransport().send(client.imageRequest(cover))
                XCTAssertEqual(response.statusCode, 200, "cover \(cover)", file: file, line: line)
            }
        }
        if let any = try await client.series(in: categories[0], page: 1, pageSize: 5).items.first {
            print("search:", (try await client.search(String(any.title.prefix(5)))).map(\.title))
        }
        print("formats opened:", opened.sorted())
        XCTAssertFalse(opened.isEmpty, "nothing opened", file: file, line: line)
        return opened
    }
}
