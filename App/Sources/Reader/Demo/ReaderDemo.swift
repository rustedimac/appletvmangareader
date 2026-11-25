import SwiftUI
import UIKit
import MangaCore

/// A self-contained reader for UI tests: launching with `-readerDemo` opens
/// `ReaderView` on a fake three-chapter series whose pages are drawn
/// locally, so XCUITests can drive page turns without a server.
///
/// Extra launch arguments (read through UserDefaults' argument domain):
/// - `-readerDirection leftToRight|rightToLeft`
/// - `-readerLayout single|double`
/// - `-readerMode paged|webtoon` and `-readerWebtoonWidth <0.3...1.0>`
/// - `-readerStartChapter <n>` (1-based) and `-readerStartPage <n>` (0-based)
enum ReaderDemo {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-readerDemo") }

    static let server = DemoMangaServer()

    struct RootView: View {
        @Environment(AppModel.self) private var model
        @State private var ready = false

        var body: some View {
            // A ZStack with a real background, not an empty Group: onAppear
            // never fires on a view with nothing in it.
            ZStack {
                Color.black.ignoresSafeArea()
                if ready {
                    let chapters = DemoMangaServer.chapters
                    let defaults = UserDefaults.standard
                    let n = max(1, min(chapters.count, defaults.integer(forKey: "readerStartChapter")))
                    let startPage = defaults.object(forKey: "readerStartPage") as? Int
                        ?? Int(defaults.string(forKey: "readerStartPage") ?? "")
                    ReaderView(series: DemoMangaServer.series, chapters: chapters, start: chapters[n - 1],
                               startPage: startPage ?? 0, server: ReaderDemo.server)
                }
            }
            .onAppear {
                var settings = ReaderSettings.default
                let defaults = UserDefaults.standard
                if let d = defaults.string(forKey: "readerDirection").flatMap(ReadingDirection.init(rawValue:)) {
                    settings.direction = d
                }
                if let l = defaults.string(forKey: "readerLayout").flatMap(PageLayout.init(rawValue:)) {
                    settings.layout = l
                }
                if let m = defaults.string(forKey: "readerMode").flatMap(ReadingMode.init(rawValue:)) {
                    settings.mode = m
                }
                if let w = Double(defaults.string(forKey: "readerWebtoonWidth") ?? "") {
                    settings.webtoonWidth = w
                }
                model.setReaderSettings(settings, for: DemoMangaServer.series.ref)
                ready = true
            }
        }
    }
}

/// Fake backend for the demo reader.
///
/// - Chapter 1: 6 pages with sizes known up front (like Kavita); page 3 is
///   a wide two-page spread.
/// - Chapter 2: 5 pages with sizes unknown until the image loads (like
///   Suwayomi); page 2 turns out to be wide.
/// - Chapter 3: 4 tall pages.
struct DemoMangaServer: MangaServer {
    let config = ServerConfig(id: UUID(uuidString: "00000000-0000-0000-0000-00000000DE30")!,
                              kind: .kavita, name: "Demo", baseURL: URL(string: "demo://server")!)

    static let seriesRef = SeriesRef(serverID: UUID(uuidString: "00000000-0000-0000-0000-00000000DE30")!, seriesID: "demo")
    static let series = SeriesSummary(ref: seriesRef, title: "Demo Series", coverURL: nil)

    /// (pixel sizes, whether the server reports them) per chapter.
    static let layouts: [(sizes: [PageSize], known: Bool)] = [
        ([tall, tall, tall, wide, tall, tall], true),
        ([tall, tall, wide, tall, tall], false),
        ([tall, tall, tall, tall], true),
    ]
    static let tall = PageSize(width: 400, height: 600)
    static let wide = PageSize(width: 800, height: 600)

    static let chapters: [Chapter] = layouts.indices.map { i in
        Chapter(id: "demo-\(i + 1)", seriesRef: seriesRef, title: "Chapter \(i + 1)",
                number: Double(i + 1), pageCount: layouts[i].sizes.count)
    }

    func validate() async throws -> String { "Demo" }
    func categories() async throws -> [MangaCategory] { [] }
    func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        Paged(items: [], hasMore: false)
    }
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] { [] }
    func search(_ query: String) async throws -> [SeriesSummary] { [] }
    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail { throw MangaError.notFound }

    func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        guard let i = Self.chapters.firstIndex(where: { $0.id == chapter.id }) else { throw MangaError.notFound }
        let layout = Self.layouts[i]
        return layout.sizes.enumerated().map { p, size in
            var c = URLComponents()
            c.scheme = DemoPageRenderer.scheme
            c.host = "page"
            c.queryItems = [
                URLQueryItem(name: "chapter", value: "\(i + 1)"),
                URLQueryItem(name: "page", value: "\(p)"),
                URLQueryItem(name: "w", value: "\(Int(size.width))"),
                URLQueryItem(name: "h", value: "\(Int(size.height))"),
            ]
            return PageDescriptor(index: p, url: c.url!, size: layout.known ? size : nil)
        }
    }

    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}
    func authorize(_ request: URLRequest) -> URLRequest { request }
}

/// Draws demo pages: a colored page with its number in the middle.
enum DemoPageRenderer {
    static let scheme = "demo"

    static func pngData(for url: URL) -> Data {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> Int { Int(items.first { $0.name == name }?.value ?? "") ?? 0 }
        let size = CGSize(width: max(1, value("w")), height: max(1, value("h")))
        let page = value("page")
        let chapter = value("chapter")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { ctx in
            let hue = CGFloat((page * 37 + chapter * 101) % 360) / 360
            UIColor(hue: hue, saturation: 0.35, brightness: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let text = "\(chapter)·\(page + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: size.height / 6),
                .foregroundColor: UIColor.black,
            ]
            let t = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2), withAttributes: attrs)
        }
    }
}
