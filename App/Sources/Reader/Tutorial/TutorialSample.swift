import SwiftUI
import MangaCore

/// The sample comic the controls tutorial reads: three pages of
/// Pepper&Carrot episode 1 (David Revoy, CC BY 4.0), bundled in
/// App/Resources/Tutorial so it works offline and before any server is
/// added. Credit: `ReaderTutorial.sampleCredit`; sources in
/// docs/TUTORIAL_SAMPLE.md.
enum TutorialSample {
    static let server = TutorialSampleServer()
    static let seriesRef = SeriesRef(serverID: TutorialSampleServer.id, seriesID: "tutorial")
    static let series = SeriesSummary(ref: seriesRef, title: "Pepper&Carrot", coverURL: nil)
    static let chapter = Chapter(id: "tutorial-1", seriesRef: seriesRef, title: "The Potion of Flight",
                                 number: 1, pageCount: ReaderTutorial.samplePageNames.count)

    /// File URLs of the bundled pages; the image pipeline reads file URLs
    /// directly.
    static var pageURLs: [URL] {
        ReaderTutorial.samplePageNames.compactMap { Bundle.main.url(forResource: $0, withExtension: "jpg") }
    }

    /// Reader settings for a run of the tutorial: left to right, one page
    /// at a time, the rest at their defaults.
    static func settings(for mode: ReadingMode) -> ReaderSettings {
        var settings = ReaderSettings.default
        settings.mode = mode
        settings.direction = .leftToRight
        settings.layout = .single
        return settings
    }
}

/// Serves the bundled sample pages. Saves nothing: the reader keeps no
/// progress, bookmarks or settings for the tutorial.
struct TutorialSampleServer: MangaServer {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-0000000075A1")!
    let config = ServerConfig(id: TutorialSampleServer.id, kind: .kavita, name: "Tutorial",
                              baseURL: URL(string: "tutorial://sample")!)

    func validate() async throws -> String { "Tutorial" }
    func categories() async throws -> [MangaCategory] { [] }
    func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        Paged(items: [], hasMore: false)
    }
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] { [] }
    func search(_ query: String) async throws -> [SeriesSummary] { [] }
    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail { throw MangaError.notFound }

    func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        let urls = TutorialSample.pageURLs
        guard !urls.isEmpty else { throw MangaError.notFound }
        return urls.enumerated().map { i, url in
            PageDescriptor(index: i, url: url, size: ReaderTutorial.samplePageSize)
        }
    }

    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}
    func markUnread(chapters: [Chapter]) async throws {}
    func markSeriesUnread(_ seriesID: String) async throws {}
    func authorize(_ request: URLRequest) -> URLRequest { request }
}

/// Remembers whether the tutorial was offered (on the first reader open)
/// or finished. UI tests get no offer unless they pass
/// `-readerTutorialOffer`, which starts from a clean slate each launch.
@MainActor
enum TutorialRecord {
    private static let offeredKey = "readerTutorial.offered"

    private static let defaults: UserDefaults? = {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting") else { return .standard }
        guard args.contains("-readerTutorialOffer"),
              let d = UserDefaults(suiteName: "uiTesting.readerTutorial") else { return nil }
        d.removeObject(forKey: offeredKey)
        return d
    }()

    /// True the first time any image reader opens.
    static var shouldOffer: Bool {
        guard let defaults else { return false }
        return !defaults.bool(forKey: offeredKey)
    }

    static func markOffered() {
        defaults?.set(true, forKey: offeredKey)
    }
}

/// The tutorial as a full-screen reader on the sample, for a
/// `fullScreenCover`. Menu closes it like any reader.
struct ReaderTutorialView: View {
    let mode: ReadingMode

    var body: some View {
        ReaderView(series: TutorialSample.series, chapters: [TutorialSample.chapter], start: TutorialSample.chapter,
                   startPage: 0, server: TutorialSample.server, tutorial: mode)
    }
}
