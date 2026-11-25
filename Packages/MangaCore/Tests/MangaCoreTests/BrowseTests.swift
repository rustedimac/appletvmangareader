import XCTest
@testable import MangaCore

private struct Item: Identifiable, Sendable, Equatable {
    var id: Int
}

final class LibraryPagerTests: XCTestCase {
    func testLoadsPagesInOrderAndStopsAtEnd() {
        var pager = LibraryPager<Item>(pageSize: 2, prefetchDistance: 0)
        XCTAssertTrue(pager.isInitialLoad)
        let t1 = pager.beginLoad()
        XCTAssertEqual(t1?.page, 1)
        XCTAssertNil(pager.beginLoad(), "no second request while one is running")
        pager.finish(t1!, Paged(items: [Item(id: 1), Item(id: 2)], hasMore: true))
        XCTAssertFalse(pager.isInitialLoad)
        let t2 = pager.beginLoad()
        XCTAssertEqual(t2?.page, 2)
        pager.finish(t2!, Paged(items: [Item(id: 3)], hasMore: false))
        XCTAssertEqual(pager.items.map(\.id), [1, 2, 3])
        XCTAssertFalse(pager.hasMore)
        XCTAssertNil(pager.beginLoad())
        XCTAssertFalse(pager.isEmpty)
    }

    func testEmptyPageEndsPagingEvenIfServerSaysMore() {
        var pager = LibraryPager<Item>(pageSize: 2)
        let t = pager.beginLoad()!
        pager.finish(t, Paged(items: [], hasMore: true))
        XCTAssertFalse(pager.hasMore)
        XCTAssertTrue(pager.isEmpty)
    }

    func testSkipsDuplicatesAcrossPages() {
        var pager = LibraryPager<Item>(pageSize: 2)
        let ticket1 = pager.beginLoad()!
        pager.finish(ticket1, Paged(items: [Item(id: 1), Item(id: 2)], hasMore: true))
        let ticket2 = pager.beginLoad()!
        pager.finish(ticket2, Paged(items: [Item(id: 2), Item(id: 3)], hasMore: true))
        XCTAssertEqual(pager.items.map(\.id), [1, 2, 3])
    }

    func testFailureBlocksUntilRetryThenRequestsSamePage() {
        var pager = LibraryPager<Item>(pageSize: 2)
        let ticket3 = pager.beginLoad()!
        pager.finish(ticket3, Paged(items: [Item(id: 1), Item(id: 2)], hasMore: true))
        let t = pager.beginLoad()!
        pager.fail(t, message: "offline")
        XCTAssertEqual(pager.errorMessage, "offline")
        XCTAssertFalse(pager.isLoading)
        XCTAssertNil(pager.beginLoad())
        XCTAssertFalse(pager.shouldLoadMore(afterShowing: 1))
        pager.retry()
        XCTAssertEqual(pager.beginLoad()?.page, 2)
    }

    func testResetIgnoresStaleResponses() {
        var pager = LibraryPager<Item>(pageSize: 2)
        let stale = pager.beginLoad()!
        pager.reset()
        pager.finish(stale, Paged(items: [Item(id: 9)], hasMore: false))
        XCTAssertTrue(pager.items.isEmpty)
        XCTAssertTrue(pager.hasMore)
        let fresh = pager.beginLoad()!
        XCTAssertEqual(fresh.page, 1)
        pager.fail(stale, message: "late error")
        XCTAssertNil(pager.errorMessage)
        XCTAssertTrue(pager.isLoading)
    }

    func testShouldLoadMoreNearTheEnd() {
        var pager = LibraryPager<Item>(pageSize: 10, prefetchDistance: 3)
        let ticket4 = pager.beginLoad()!
        pager.finish(ticket4, Paged(items: (1...10).map { Item(id: $0) }, hasMore: true))
        XCTAssertFalse(pager.shouldLoadMore(afterShowing: 5))
        XCTAssertTrue(pager.shouldLoadMore(afterShowing: 6))
        XCTAssertTrue(pager.shouldLoadMore(afterShowing: 9))
        _ = pager.beginLoad()
        XCTAssertFalse(pager.shouldLoadMore(afterShowing: 9), "already loading")
    }
}

final class ChapterDisplayTests: XCTestCase {
    let ref = SeriesRef(serverID: UUID(), seriesID: "1")

    func chapter(_ n: Int, read: Bool = false, page: Int = 0, count: Int = 20) -> Chapter {
        Chapter(id: "\(n)", seriesRef: ref, title: "Chapter \(n)", number: Double(n), pageCount: count,
                lastPageRead: page, isRead: read)
    }

    func detail(_ chapters: [Chapter]) -> SeriesDetail {
        SeriesDetail(summary: SeriesSummary(ref: ref, title: "T", coverURL: nil), synopsis: nil,
                     authors: [], genres: [], status: nil, chapters: chapters)
    }

    func testReadStates() {
        XCTAssertEqual(chapter(1).readState, .unread)
        XCTAssertEqual(chapter(1, read: true, page: 5).readState, .read)
        XCTAssertEqual(chapter(1, page: 4).readState, .inProgress(page: 5, pageCount: 20))
        XCTAssertEqual(chapter(1, page: 4).readState.label, "Page 5 of 20")
        XCTAssertEqual(chapter(1, page: 4, count: -1).readState.label, "Page 5", "Suwayomi before pages are fetched")
        XCTAssertEqual(chapter(1).readState.label, "")
    }

    func testContinueAction() {
        XCTAssertNil(detail([]).continueAction)
        XCTAssertEqual(detail([chapter(1), chapter(2)]).continueAction?.label, "Start Reading")
        XCTAssertEqual(detail([chapter(1), chapter(2)]).continueAction?.chapter.id, "1")

        let partway = detail([chapter(1, read: true), chapter(2, page: 3), chapter(3)])
        XCTAssertEqual(partway.continueAction?.label, "Continue Chapter 2")
        XCTAssertEqual(partway.continueAction?.chapter.id, "2")

        let midFirst = detail([chapter(1, page: 3), chapter(2)])
        XCTAssertEqual(midFirst.continueAction?.label, "Continue Chapter 1")

        let done = detail([chapter(1, read: true), chapter(2, read: true)])
        XCTAssertEqual(done.continueAction?.label, "Read Again")
        XCTAssertEqual(done.continueAction?.chapter.id, "1")
        XCTAssertEqual(done.readCount, 2)
    }

    func testDisplayOrder() {
        let d = detail([chapter(1), chapter(2), chapter(3)])
        XCTAssertEqual(d.displayChapters(newestFirst: false).map(\.id), ["1", "2", "3"])
        XCTAssertEqual(d.displayChapters(newestFirst: true).map(\.id), ["3", "2", "1"])
    }
}

/// A server whose every call fails, for error paths.
private struct FailingServer: MangaServer {
    var config: ServerConfig
    func validate() async throws -> String { throw MangaError.unauthorized }
    func categories() async throws -> [MangaCategory] { throw MangaError.unauthorized }
    func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> { throw MangaError.unauthorized }
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] { throw MangaError.unauthorized }
    func search(_ query: String) async throws -> [SeriesSummary] { throw MangaError.unauthorized }
    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail { throw MangaError.notFound }
    func pages(for chapter: Chapter) async throws -> [PageDescriptor] { throw MangaError.notFound }
    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}
    func authorize(_ request: URLRequest) -> URLRequest { request }
}

final class BrowseLoaderTests: XCTestCase {
    func demo(_ name: String, count: Int = 30) -> SampleLibraryServer {
        SampleLibraryServer(config: ServerConfig(kind: .kavita, name: name, baseURL: URL(string: "https://demo.invalid")!),
                        seriesCount: count, latency: .zero)
    }

    func testHomeKeepsServerOrderAndDropsEmptyRows() async {
        let a = demo("A"), b = demo("B")
        let sections = await HomeLoader.load([HomeSource(server: a), HomeSource(server: b)], limit: 5)
        XCTAssertEqual(sections.map(\.server.name), ["A", "B"])
        // Nothing read yet, so no Continue Reading row.
        XCTAssertEqual(sections[0].rows.map(\.feed), [.recentlyUpdated, .newlyAdded])
        XCTAssertEqual(sections[0].rows[0].series.count, 5)
        XCTAssertNil(sections[0].errorMessage)
    }

    func testHomeContinueReadingRespectsSyncSetting() async throws {
        let a = demo("A")
        let detail = try await a.seriesDetail("4")
        try await a.saveProgress(chapter: detail.chapters[0], libraryID: nil, page: 2, completed: false)

        let synced = await HomeLoader.load(HomeSource(server: a, includeContinueReading: true))
        XCTAssertEqual(synced.rows.first?.feed, .continueReading)
        XCTAssertEqual(synced.rows.first?.series.map(\.ref.seriesID), ["4"])

        let local = await HomeLoader.load(HomeSource(server: a, includeContinueReading: false))
        XCTAssertFalse(local.rows.contains { $0.feed == .continueReading })
    }

    func testHomeReportsErrorOnlyWhenEverythingFails() async {
        let bad = FailingServer(config: ServerConfig(kind: .suwayomi, name: "Down", baseURL: URL(string: "http://x")!))
        let section = await HomeLoader.load(HomeSource(server: bad))
        XCTAssertTrue(section.rows.isEmpty)
        XCTAssertEqual(section.errorMessage, MangaError.unauthorized.errorDescription)
    }

    func testSearchGroupsByServerAndKeepsErrors() async {
        let a = demo("A", count: 16), b = demo("B", count: 8)
        let bad = FailingServer(config: ServerConfig(kind: .suwayomi, name: "Down", baseURL: URL(string: "http://x")!))
        let results = await CrossServerSearch.run("  lantern ", on: [a, bad, b])
        XCTAssertEqual(results.map(\.server.name), ["A", "Down", "B"])
        XCTAssertEqual(results[0].series.map(\.title), ["Lantern Chronicles 3", "Lantern Chronicles 11"])
        XCTAssertEqual(results[2].series.map(\.title), ["Lantern Chronicles 3"])
        XCTAssertNotNil(results[1].errorMessage)
    }

    func testSearchDropsServersWithNoMatches() async {
        let results = await CrossServerSearch.run("nothing-matches", on: [demo("A")])
        XCTAssertTrue(results.isEmpty)
        let blank = await CrossServerSearch.run("   ", on: [demo("A")])
        XCTAssertTrue(blank.isEmpty)
        XCTAssertNil(CrossServerSearch.normalize(" \n"))
    }
}

final class DemoServerTests: XCTestCase {
    func testPagingCoversEverySeriesOnce() async throws {
        let server = SampleLibraryServer(config: ServerConfig(kind: .kavita, name: "D", baseURL: URL(string: "https://demo.invalid")!),
                                     seriesCount: 50, latency: .zero)
        let all = MangaCategory(id: "all", name: "All")
        var pager = LibraryPager<SeriesSummary>(pageSize: 12)
        while let ticket = pager.beginLoad() {
            let page = try await server.series(in: all, page: ticket.page, pageSize: 12)
            pager.finish(ticket, page)
        }
        XCTAssertEqual(pager.items.count, 50)
        XCTAssertEqual(Set(pager.items.map(\.ref.seriesID)).count, 50)

        let short = try await server.series(in: MangaCategory(id: "short", name: "S"), page: 1, pageSize: 100)
        XCTAssertEqual(short.items.count, 16)
        XCTAssertFalse(short.hasMore)
    }

    func testProgressShowsInDetail() async throws {
        let server = SampleLibraryServer(config: ServerConfig(kind: .suwayomi, name: "D", baseURL: URL(string: "https://demo.invalid")!),
                                     latency: .zero)
        var detail = try await server.seriesDetail("2")
        XCTAssertEqual(detail.continueAction?.label, "Start Reading")
        try await server.saveProgress(chapter: detail.chapters[0], libraryID: nil, page: 19, completed: true)
        detail = try await server.seriesDetail("2")
        XCTAssertTrue(detail.chapters[0].isRead)
        XCTAssertEqual(detail.continueAction?.chapter.id, detail.chapters[1].id)
        do {
            _ = try await server.seriesDetail("999")
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? MangaError, .notFound)
        }
    }
}
