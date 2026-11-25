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

    func testCategoriesSorted() async throws {
        mock.onGraphQL("categories", body: #"{"data":{"categories":{"nodes":[{"id":2,"name":"Reading","order":2},{"id":0,"name":"Default","order":0},{"id":1,"name":"Webtoon","order":1}]}}}"#)
        let cats = try await client.categories()
        XCTAssertEqual(cats.map(\.name), ["Default", "Webtoon", "Reading"])
    }

    func testCategorySeriesPagedClientSide() async throws {
        mock.onGraphQL("category(id", body: """
        {"data":{"category":{"mangas":{"nodes":[
          {"id":3,"title":"Chainsaw Man","thumbnailUrl":"/api/v1/manga/3/thumbnail","unreadCount":2,"inLibrary":true},
          {"id":1,"title":"Berserk","thumbnailUrl":"/api/v1/manga/1/thumbnail","unreadCount":0,"inLibrary":true},
          {"id":2,"title":"Akira","thumbnailUrl":null,"unreadCount":0,"inLibrary":false}
        ]}}}}
        """)
        let cat = MangaCategory(id: "1", name: "Manga")
        let p1 = try await client.series(in: cat, page: 1, pageSize: 1)
        XCTAssertEqual(p1.items.map(\.title), ["Berserk"])
        XCTAssertTrue(p1.hasMore)
        XCTAssertEqual(p1.items[0].coverURL?.absoluteString, "http://suwayomi.local:4567/api/v1/manga/1/thumbnail")
        let p2 = try await client.series(in: cat, page: 2, pageSize: 1)
        XCTAssertEqual(p2.items.map(\.title), ["Chainsaw Man"])
        XCTAssertFalse(p2.hasMore)
        let p3 = try await client.series(in: cat, page: 3, pageSize: 1)
        XCTAssertTrue(p3.items.isEmpty)
        let vars = jsonBody(mock.lastRequest(containing: "category(id"))["variables"] as? [String: Any]
        XCTAssertEqual(vars?["id"] as? Int, 1)
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
        mock.onGraphQL("IN_LIBRARY_AT", body: #"{"data":{"mangas":{"nodes":[{"id":9,"title":"New One","chapters":{"totalCount":42}},{"id":10,"title":"Older"}]}}}"#)
        let items = try await client.feed(.newlyAdded, limit: 5)
        XCTAssertEqual(items.map(\.title), ["New One", "Older"])
        XCTAssertEqual(items.map(\.chapterCount), [42, nil], "home rows carry the chapter count")
    }

    func testSeriesDetailChapterOrder() async throws {
        // sourceOrder ascending is oldest first here; numbers confirm it.
        mock.onGraphQL("manga(id", body: """
        {"data":{"manga":{"id":4,"title":"Frieren","description":"Elf.","author":"Yamada","artist":"Abe","genre":["Fantasy"],"status":"ONGOING","thumbnailUrl":"/api/v1/manga/4/thumbnail","unreadCount":1,
         "chapters":{"nodes":[
           {"id":12,"name":"Chapter 2","chapterNumber":2,"sourceOrder":2,"isRead":false,"lastPageRead":3,"pageCount":-1,"uploadDate":"1700000000000"},
           {"id":11,"name":"Chapter 1","chapterNumber":1,"sourceOrder":1,"isRead":true,"lastPageRead":0,"pageCount":18,"uploadDate":"1690000000000"}
         ]}}}}
        """)
        let d = try await client.seriesDetail("4")
        XCTAssertEqual(d.chapters.map(\.id), ["11", "12"])
        XCTAssertEqual(d.chapters[1].pageCount, 0) // -1 means "not fetched yet"
        XCTAssertEqual(d.chapters[1].lastPageRead, 3)
        XCTAssertEqual(d.chapters[0].updatedAt, Date(timeIntervalSince1970: 1_690_000_000))
        XCTAssertEqual(d.authors, ["Yamada", "Abe"])
        XCTAssertEqual(d.status, "Ongoing")
        XCTAssertEqual(d.continueChapter?.id, "12")
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
