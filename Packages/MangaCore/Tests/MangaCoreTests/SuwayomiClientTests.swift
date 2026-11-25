import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class SuwayomiClientTests: XCTestCase {
    let config = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local:4567/")!)
    var mock: MockTransport!
    var client: SuwayomiClient!

    override func setUp() {
        mock = MockTransport()
        client = SuwayomiClient(config: config, username: nil, password: nil, transport: mock)
    }

    func testValidate() async throws {
        mock.onGraphQL("aboutServer", body: #"{"data":{"aboutServer":{"name":"Suwayomi-Server","version":"v2.4.2366"}}}"#)
        let s = try await client.validate()
        XCTAssertEqual(s, "Connected to Suwayomi-Server v2.4.2366")
        XCTAssertNil(mock.requests.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(mock.requests.last?.url?.absoluteString, "http://suwayomi.local:4567/api/graphql")
    }

    func testBasicAuthHeader() async throws {
        let c = SuwayomiClient(config: config, username: "john", password: "pw", transport: mock)
        mock.onGraphQL("aboutServer", body: #"{"data":{"aboutServer":{"name":"S","version":"1"}}}"#)
        _ = try await c.validate()
        XCTAssertEqual(mock.requests.last?.value(forHTTPHeaderField: "Authorization"), "Basic am9objpwdw==")
        let img = c.imageRequest(URL(string: "http://suwayomi.local:4567/api/v1/manga/1/thumbnail")!)
        XCTAssertEqual(img.value(forHTTPHeaderField: "Authorization"), "Basic am9objpwdw==")
    }

    func testGraphQLErrorsSurface() async {
        mock.onGraphQL("categories", body: #"{"data":null,"errors":[{"message":"boom"}]}"#)
        do {
            _ = try await client.categories()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MangaError, .graphQL(["boom"]))
        }
    }

    func testCategoriesSortedAndEmptyDefaultHidden() async throws {
        mock.onGraphQL("categories", body: fixture("suwayomi-categories"))
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.name), ["KR", "JP", "EN"])
        XCTAssertEqual(cats.map(\.id), ["2", "3", "4"])
        XCTAssertTrue(graphQLQuery(mock, "categories").contains("totalCount"))
    }

    func testDefaultCategoryShownWhenItHasManga() async throws {
        mock.onGraphQL("categories", body: #"{"data":{"categories":{"nodes":[{"id":0,"name":"Default","order":0,"mangas":{"totalCount":4}},{"id":1,"name":"Webtoon","order":1,"mangas":{"totalCount":9}}]}}}"#)
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.name), ["Default", "Webtoon"])
    }

    func testCategorySeriesPagedOnServer() async throws {
        mock.onGraphQL(all: ["mangas(condition", "\"offset\":2"], body: fixture("suwayomi-category-page"))
        mock.onGraphQL(all: ["mangas(condition", "\"offset\":700"], body: fixture("suwayomi-category-last-page"))
        let cat = MangaCategory(id: "2", name: "KR")
        let p2 = try await client.series(in: cat, page: 2, pageSize: 2)
        XCTAssertEqual(p2.items.map(\.title), ["Harbor Lights", "Iron Orchard"])
        XCTAssertEqual(p2.items.map(\.unreadCount), [8, 12])
        XCTAssertEqual(p2.items[0].coverURL?.absoluteString, "http://suwayomi.local:4567/api/v1/manga/16109/thumbnail")
        XCTAssertTrue(p2.hasMore)
        let vars = graphQLVariables(mock, "\"offset\":2")
        XCTAssertEqual(vars["ids"] as? [Int], [2])
        XCTAssertEqual(vars["first"] as? Int, 2)
        XCTAssertEqual(vars["offset"] as? Int, 2)
        let query = graphQLQuery(mock, "\"offset\":2")
        XCTAssertTrue(query.contains("categoryIds: $ids"), query)
        XCTAssertTrue(query.contains("orderBy: TITLE"), query)
        XCTAssertFalse(query.contains("category(id"), "category.mangas takes no paging arguments")

        let last = try await client.series(in: cat, page: 351, pageSize: 2)
        XCTAssertEqual(last.items.map(\.title), ["Zephyr Line"])
        XCTAssertFalse(last.hasMore)
    }

    func testServerPagingFallsBackToTotalCount() async throws {
        mock.onGraphQL("mangas(condition", body: #"{"data":{"mangas":{"totalCount":3,"nodes":[{"id":1,"title":"A"},{"id":2,"title":"B"}]}}}"#)
        let page = try await client.series(in: MangaCategory(id: "5", name: "X"), page: 1, pageSize: 2)
        XCTAssertTrue(page.hasMore)
    }

    func testDefaultCategoryPagedClientSide() async throws {
        mock.onGraphQL("category(id", body: """
        {"data":{"category":{"mangas":{"nodes":[
          {"id":3,"title":"Copper Kettle","thumbnailUrl":"/api/v1/manga/3/thumbnail","unreadCount":2,"inLibrary":true},
          {"id":1,"title":"Amber Road","thumbnailUrl":"/api/v1/manga/1/thumbnail","unreadCount":0,"inLibrary":true},
          {"id":2,"title":"Blue Ferry","thumbnailUrl":null,"unreadCount":0,"inLibrary":false}
        ]}}}}
        """)
        let cat = MangaCategory(id: "0", name: "Default")
        let p1 = try await client.series(in: cat, page: 1, pageSize: 1)
        XCTAssertEqual(p1.items.map(\.title), ["Amber Road"])
        XCTAssertTrue(p1.hasMore)
        let p2 = try await client.series(in: cat, page: 2, pageSize: 1)
        XCTAssertEqual(p2.items.map(\.title), ["Copper Kettle"])
        XCTAssertFalse(p2.hasMore)
        let p3 = try await client.series(in: cat, page: 3, pageSize: 1)
        XCTAssertTrue(p3.items.isEmpty)
        XCTAssertEqual(graphQLVariables(mock, "category(id")["id"] as? Int, 0)
    }

    func testOldPagingErrorSurfaces() async {
        // What the live server says if paging args are put on category.mangas.
        mock.onGraphQL("mangas(condition", body: fixture("suwayomi-category-error"))
        do {
            _ = try await client.series(in: MangaCategory(id: "2", name: "KR"), page: 1, pageSize: 2)
            XCTFail("expected error")
        } catch {
            guard case .graphQL(let messages)? = error as? MangaError else { return XCTFail("\(error)") }
            XCTAssertTrue(messages.first?.contains("UnknownArgument") ?? false)
        }
    }

    func testChapterFeedsDedupeAndFilterUnread() async throws {
        mock.onGraphQL("LAST_READ_AT", body: """
        {"data":{"chapters":{"nodes":[
          {"lastReadAt":"1732500000","manga":{"id":5,"title":"A"}},
          {"lastReadAt":"1732400000","manga":{"id":5,"title":"A"}},
          {"lastReadAt":"0","manga":{"id":6,"title":"Never Read"}},
          {"lastReadAt":"1732300000","manga":{"id":7,"title":"B"}}
        ]}}}
        """)
        mock.onGraphQL("FETCHED_AT", body: """
        {"data":{"chapters":{"nodes":[
          {"lastReadAt":"0","manga":{"id":6,"title":"Fresh"}},
          {"lastReadAt":"0","manga":{"id":6,"title":"Fresh"}},
          {"lastReadAt":"0","manga":{"id":8,"title":"Also Fresh"}}
        ]}}}
        """)
        let reading = try await client.feed(.continueReading, limit: 10)
        XCTAssertEqual(reading.map(\.title), ["A", "B"])
        let updated = try await client.feed(.recentlyUpdated, limit: 1)
        XCTAssertEqual(updated.map(\.title), ["Fresh"])
    }

    func testNewlyAddedQuery() async throws {
        mock.onGraphQL("IN_LIBRARY_AT", body: #"{"data":{"mangas":{"nodes":[{"id":9,"title":"New One"}]}}}"#)
        let items = try await client.feed(.newlyAdded, limit: 5)
        XCTAssertEqual(items.map(\.title), ["New One"])
    }

    func testSeriesDetailUsesSourceOrder() async throws {
        mock.onGraphQL("manga(id", body: fixture("suwayomi-manga-detail"))
        let d = try await client.seriesDetail("16109")
        let query = graphQLQuery(mock, "manga(id")
        XCTAssertTrue(query.contains("chapters(condition: {mangaId: $id}, orderBy: SOURCE_ORDER, orderByType: ASC)"), query)
        XCTAssertEqual(d.summary.title, "Harbor Lights")
        XCTAssertEqual(d.chapters.map(\.id), ["93233", "93234", "93235"])
        XCTAssertEqual(d.chapters.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(d.chapters[2].pageCount, 0) // -1 means "not fetched yet"
        XCTAssertEqual(d.chapters[1].lastPageRead, 8)
        XCTAssertFalse(d.chapters[1].isRead) // lastPageRead > 0 while unread is normal
        XCTAssertEqual(d.chapters[0].updatedAt, Date(timeIntervalSince1970: 1_572_580_800))
        XCTAssertEqual(d.authors, ["Mina Ro"])
        XCTAssertEqual(d.genres, ["Drama", "Slice of Life"])
        XCTAssertEqual(d.status, "Ongoing")
        XCTAssertEqual(d.continueChapter?.id, "93234")
    }

    func testUnnumberedChaptersFollowSourceOrder() async throws {
        // chapterNumber -1 everywhere; ids run the opposite way to sourceOrder.
        mock.onGraphQL("manga(id", body: fixture("suwayomi-unnumbered-chapters"))
        let d = try await client.seriesDetail("10")
        XCTAssertEqual(d.chapters.map(\.id), ["16", "11", "10"])
        XCTAssertEqual(d.chapters.map(\.title), ["Side Story", "Prologue", "Chapter 3"])
        XCTAssertEqual(d.chapters.map(\.number), [1, 2, 3])
    }

    func testChapterTitleFallbacks() {
        XCTAssertEqual(SuwayomiClient.title(for: SuwayomiChapterDTO(id: 1, name: "  ", chapterNumber: 12.5), position: 4), "Chapter 12.5")
        XCTAssertEqual(SuwayomiClient.title(for: SuwayomiChapterDTO(id: 1, name: nil, chapterNumber: -1), position: 4), "Chapter 4")
        XCTAssertEqual(SuwayomiClient.title(for: SuwayomiChapterDTO(id: 1, name: "Ep. 7", chapterNumber: -1), position: 4), "Ep. 7")
    }

    func testChapterOrderReversedWhenSourceIsNewestFirst() {
        let ref = SeriesRef(serverID: config.id, seriesID: "1")
        let nodes = [
            SuwayomiChapterDTO(id: 1, name: "Ch 3", chapterNumber: 3, sourceOrder: 0),
            SuwayomiChapterDTO(id: 2, name: "Ch 2", chapterNumber: 2, sourceOrder: 1),
            SuwayomiChapterDTO(id: 3, name: "Ch 1", chapterNumber: 1, sourceOrder: 2),
        ]
        XCTAssertEqual(SuwayomiClient.chapters(from: nodes, seriesRef: ref).map(\.title), ["Ch 1", "Ch 2", "Ch 3"])
    }

    func testUnknownNumbersDoNotFlipOrder() {
        // A -1 extra between numbered chapters must not trigger a reversal.
        let ref = SeriesRef(serverID: config.id, seriesID: "1")
        let nodes = [
            SuwayomiChapterDTO(id: 1, name: "Ch 1", chapterNumber: 1, sourceOrder: 1),
            SuwayomiChapterDTO(id: 2, name: "Extra", chapterNumber: -1, sourceOrder: 2),
            SuwayomiChapterDTO(id: 3, name: "Ch 2", chapterNumber: 2, sourceOrder: 3),
        ]
        XCTAssertEqual(SuwayomiClient.chapters(from: nodes, seriesRef: ref).map(\.title), ["Ch 1", "Extra", "Ch 2"])
    }

    func testPagesResolveRelativeURLs() async throws {
        mock.onGraphQL("fetchChapterPages", body: #"{"data":{"fetchChapterPages":{"pages":["/api/v1/manga/4/chapter/1/page/0","/api/v1/manga/4/chapter/1/page/1"]}}}"#)
        let ref = SeriesRef(serverID: config.id, seriesID: "4")
        let pages = try await client.pages(for: Chapter(id: "11", seriesRef: ref, title: "1", number: 1, pageCount: 0))
        XCTAssertEqual(pages.map(\.url.absoluteString), [
            "http://suwayomi.local:4567/api/v1/manga/4/chapter/1/page/0",
            "http://suwayomi.local:4567/api/v1/manga/4/chapter/1/page/1",
        ])
        XCTAssertEqual(pages.map(\.index), [0, 1])
        XCTAssertNil(pages[0].size)
    }

    func testSaveProgressMutation() async throws {
        mock.onGraphQL("updateChapter", body: #"{"data":{"updateChapter":{"clientMutationId":null}}}"#)
        let ref = SeriesRef(serverID: config.id, seriesID: "4")
        try await client.saveProgress(chapter: Chapter(id: "11", seriesRef: ref, title: "1", number: 1, pageCount: 10),
                                      libraryID: nil, page: 7, completed: true)
        let vars = jsonBody(mock.lastRequest(containing: "updateChapter"))["variables"] as? [String: Any]
        XCTAssertEqual(vars?["id"] as? Int, 11)
        XCTAssertEqual(vars?["page"] as? Int, 7)
        XCTAssertEqual(vars?["read"] as? Bool, true)
    }

    func testResolveKeepsPathPrefix() {
        let c = SuwayomiClient(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "https://h.example/suwa")!),
                               username: nil, password: nil, transport: mock)
        XCTAssertEqual(c.resolve("/api/v1/manga/1/thumbnail")?.absoluteString, "https://h.example/suwa/api/v1/manga/1/thumbnail")
        XCTAssertEqual(c.resolve("https://cdn.example/x.jpg")?.absoluteString, "https://cdn.example/x.jpg")
        XCTAssertNil(c.resolve(nil))
        XCTAssertNil(c.resolve(""))
    }
}
