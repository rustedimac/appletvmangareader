import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Kavita reading lists, collections and smart filters. Response bodies
/// follow Kavita 0.8/0.9 DTOs, with made-up titles.
final class KavitaCollectionsTests: XCTestCase {
    let config = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
    var mock: MockTransport!

    override func setUp() {
        mock = MockTransport()
    }

    private func client(scope: Set<String>? = nil) -> KavitaClient {
        KavitaClient(config: config, apiKey: "KEY", categoryScope: scope, transport: mock)
    }

    func testKavitaSupportsAllKinds() {
        XCTAssertEqual(client().collectionSupport.kinds, [.readingList, .collection, .smartFilter])
    }

    func testOtherServersOfferNone() {
        let suwayomi = MangaServerFactory.make(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: config.baseURL),
                                               credential: nil, transport: mock)
        let komga = MangaServerFactory.make(config: ServerConfig(kind: .komga, name: "K", baseURL: config.baseURL),
                                            credential: nil, transport: mock)
        XCTAssertEqual(suwayomi.collectionSupport, [])
        XCTAssertEqual(komga.collectionSupport, [])
    }

    func testOtherServersReturnNothingWithoutCalls() async throws {
        let opds = MangaServerFactory.make(config: ServerConfig(kind: .opds, name: "O", baseURL: config.baseURL),
                                           credential: nil, transport: mock)
        let lists = try await opds.collections(.readingList)
        XCTAssertTrue(lists.isEmpty)
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testReadingLists() async throws {
        mock.on("POST", "api/ReadingList/lists", body: """
        [{"id":3,"title":"Summer Arc","summary":"  ","promoted":true,"itemCount":12,"ageRating":0},
         {"id":4,"title":"","promoted":false,"itemCount":1}]
        """)
        let lists = try await client().collections(.readingList)
        XCTAssertEqual(lists.map(\.title), ["Summer Arc", "Untitled"])
        XCTAssertEqual(lists.first?.kind, .readingList)
        XCTAssertEqual(lists.first?.collectionID, "3")
        XCTAssertNil(lists.first?.summary)
        XCTAssertEqual(lists.first?.caption, "12 items · Promoted")
        XCTAssertEqual(lists.last?.caption, "1 item")
        XCTAssertEqual(lists.first?.coverURL?.absoluteString,
                       "http://kavita.local:5000/api/Image/readinglist-cover?apiKey=KEY&readingListId=3")
        let url = try XCTUnwrap(mock.lastRequest(containing: "ReadingList/lists")?.url?.absoluteString)
        XCTAssertTrue(url.contains("includePromoted=true"), url)
        XCTAssertTrue(url.contains("pageSize=0"), url) // 0 = everything
        XCTAssertEqual(mock.lastRequest(containing: "ReadingList/lists")?.value(forHTTPHeaderField: "x-api-key"), "KEY")
    }

    func testCollections() async throws {
        mock.on("GET", "api/Collection", body: """
        [{"id":7,"title":"Sea Stories","summary":"Boats.","promoted":false,"itemCount":5,"owner":"john","source":0}]
        """)
        let tags = try await client().collections(.collection)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].title, "Sea Stories")
        XCTAssertEqual(tags[0].summary, "Boats.")
        XCTAssertEqual(tags[0].caption, "5 series")
        XCTAssertEqual(tags[0].coverURL?.absoluteString,
                       "http://kavita.local:5000/api/Image/collection-cover?apiKey=KEY&collectionTagId=7")
        XCTAssertTrue(mock.lastRequest(containing: "api/Collection")?.url?.absoluteString.contains("ownedOnly=false") == true)
    }

    func testSmartFiltersKeepOnlySeriesFilters() async throws {
        mock.on("GET", "api/filter", body: """
        [{"id":1,"name":"Unread Ongoing","filter":"name=Unread%20Ongoing&stmts=comparison%3D0","entityType":0},
         {"id":2,"name":"People","filter":"stmts=x","entityType":2},
         {"id":3,"name":"Old Server","filter":"stmts=y"},
         {"id":4,"name":"Broken","filter":""}]
        """)
        let filters = try await client().collections(.smartFilter)
        XCTAssertEqual(filters.map(\.title), ["Unread Ongoing", "Old Server"])
        XCTAssertEqual(filters.first?.payload, "name=Unread%20Ongoing&stmts=comparison%3D0")
        XCTAssertNil(filters.first?.caption)
    }

    func testSeriesInCollectionPagesOnTheServer() async throws {
        mock.on("GET", "api/Series/series-by-collection", body: """
        [{"id":5,"name":"Harbor Lights","pages":40,"pagesRead":0,"libraryId":1},
         {"id":6,"name":"Second Harbor","pages":10,"pagesRead":0,"libraryId":9}]
        """)
        let collection = ServerCollection(serverID: config.id, kind: .collection, collectionID: "7", title: "Sea")
        let page = try await client().series(in: collection, page: 2, pageSize: 2)
        XCTAssertEqual(page.items.map(\.title), ["Harbor Lights", "Second Harbor"])
        XCTAssertTrue(page.hasMore) // the server's page was full
        let url = try XCTUnwrap(mock.lastRequest(containing: "series-by-collection")?.url?.absoluteString)
        XCTAssertTrue(url.contains("collectionId=7"), url)
        XCTAssertTrue(url.contains("pageNumber=2"), url)
        XCTAssertTrue(url.contains("pageSize=2"), url)
    }

    func testScopedCollectionLoadsWholeAndNarrows() async throws {
        mock.on("GET", "api/Series/series-by-collection", body: """
        [{"id":5,"name":"Harbor Lights","pages":40,"pagesRead":0,"libraryId":1},
         {"id":6,"name":"Hidden Library Series","pages":10,"pagesRead":0,"libraryId":9}]
        """)
        let collection = ServerCollection(serverID: config.id, kind: .collection, collectionID: "7", title: "Sea")
        let scoped = client(scope: ["1"])
        let first = try await scoped.series(in: collection, page: 1, pageSize: 1)
        XCTAssertEqual(first.items.map(\.title), ["Harbor Lights"]) // library 9 isn't picked
        XCTAssertFalse(first.hasMore)
        let url = try XCTUnwrap(mock.lastRequest(containing: "series-by-collection")?.url?.absoluteString)
        XCTAssertTrue(url.contains("pageSize=0"), url)
        let count = mock.requests.count
        let second = try await scoped.series(in: collection, page: 2, pageSize: 1)
        XCTAssertTrue(second.items.isEmpty)
        XCTAssertEqual(mock.requests.count, count)
    }

    func testScopedAndSmartFilterAddsALibraryStatement() async throws {
        mock.on("POST", "api/filter/decode", body: """
        {"statements":[{"comparison":0,"field":20,"value":"0"}],"combination":1,"limitTo":0}
        """)
        mock.on("POST", "api/Series/all-v2", body: "[]")
        let filter = ServerCollection(serverID: config.id, kind: .smartFilter, collectionID: "1", title: "Unread", payload: "x")
        _ = try await client(scope: ["3", "1"]).series(in: filter, page: 2, pageSize: 10)
        let sent = jsonBody(mock.lastRequest(containing: "all-v2"))
        let statements = try XCTUnwrap(sent["statements"] as? [[String: Any]])
        XCTAssertEqual(statements.last?["field"] as? Int, 19)
        XCTAssertEqual(statements.last?["value"] as? String, "1,3")
        XCTAssertEqual(sent["combination"] as? Int, 1)
        XCTAssertTrue(mock.lastRequest(containing: "all-v2")?.url?.absoluteString.contains("pageNumber=2") == true)
    }

    func testScopedOrSmartFilterLoadsWholeAndNarrows() async throws {
        mock.on("POST", "api/filter/decode", body: """
        {"statements":[{"comparison":0,"field":20,"value":"0"},{"comparison":0,"field":2,"value":"1"}],"combination":0}
        """)
        mock.on("POST", "api/Series/all-v2", body: """
        [{"id":5,"name":"Harbor Lights","libraryId":1},{"id":6,"name":"Elsewhere","libraryId":9}]
        """)
        let filter = ServerCollection(serverID: config.id, kind: .smartFilter, collectionID: "1", title: "Or", payload: "x")
        let page = try await client(scope: ["1"]).series(in: filter, page: 1, pageSize: 10)
        XCTAssertEqual(page.items.map(\.title), ["Harbor Lights"])
        XCTAssertFalse(page.hasMore)
        let sent = jsonBody(mock.lastRequest(containing: "all-v2"))
        XCTAssertEqual((sent["statements"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(sent["combination"] as? Int, 0)
        XCTAssertTrue(mock.lastRequest(containing: "all-v2")?.url?.absoluteString.contains("pageSize=0") == true)
    }

    func testSmartFilterDecodesThenSendsTheFilterUnchanged() async throws {
        mock.on("POST", "api/filter/decode", body: """
        {"id":0,"name":"Unread Ongoing","statements":[{"comparison":0,"field":20,"value":"0"},
         {"comparison":5,"field":2,"value":"0"}],"combination":0,"sortOptions":{"sortField":1,"isAscending":true},
         "limitTo":0,"entityType":0}
        """)
        mock.on("POST", "api/Series/all-v2", body: #"[{"id":8,"name":"Lantern Road","pages":30,"pagesRead":0,"libraryId":2}]"#)
        let filter = ServerCollection(serverID: config.id, kind: .smartFilter, collectionID: "1", title: "Unread",
                                      payload: "name=Unread%20Ongoing&stmts=x")
        let page = try await client().series(in: filter, page: 1, pageSize: 50)
        XCTAssertEqual(page.items.map(\.title), ["Lantern Road"])
        XCTAssertFalse(page.hasMore)

        let decode = jsonBody(mock.lastRequest(containing: "filter/decode"))
        XCTAssertEqual(decode["encodedFilter"] as? String, "name=Unread%20Ongoing&stmts=x")
        let sent = jsonBody(mock.lastRequest(containing: "all-v2"))
        XCTAssertEqual(sent["combination"] as? Int, 0) // Or stays Or: no library statement is added
        let statements = try XCTUnwrap(sent["statements"] as? [[String: Any]])
        XCTAssertEqual(statements.map { $0["field"] as? Int }, [20, 2])
        XCTAssertEqual((sent["sortOptions"] as? [String: Any])?["sortField"] as? Int, 1)
    }

    func testNothingPickedLoadsNothing() async throws {
        let collection = ServerCollection(serverID: config.id, kind: .collection, collectionID: "7", title: "Sea")
        let page = try await client(scope: []).series(in: collection, page: 1, pageSize: 20)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testReadingListEntriesInOrder() async throws {
        mock.on("GET", "api/ReadingList/items", body: """
        [{"id":21,"order":1,"chapterId":102,"seriesId":5,"seriesName":"Harbor Lights","seriesFormat":1,
          "pagesRead":3,"pagesTotal":20,"chapterNumber":"2","volumeId":50,"libraryId":1,"title":"",
          "chapter":{"id":102,"range":"2","titleName":"The Pier","pages":20}},
         {"id":20,"order":0,"chapterId":101,"seriesId":5,"seriesName":"Harbor Lights","seriesFormat":1,
          "pagesRead":18,"pagesTotal":18,"volumeId":50,"libraryId":1,"title":"Volume 1"},
         {"id":22,"order":2,"chapterId":300,"seriesId":9,"seriesName":"Elsewhere","pagesRead":0,"pagesTotal":5,
          "libraryId":4,"title":"Chapter 1"}]
        """)
        let list = ServerCollection(serverID: config.id, kind: .readingList, collectionID: "3", title: "Arc")
        let entries = try await client(scope: ["1"]).readingListEntries(list)
        XCTAssertEqual(entries.map(\.itemID), ["20", "21"]) // list order; library 4 not picked
        XCTAssertEqual(entries.map(\.title), ["Volume 1", "Chapter 2: The Pier"])
        XCTAssertEqual(entries[1].chapterID, "102")
        XCTAssertEqual(entries[1].volumeID, "50")
        XCTAssertEqual(entries[1].seriesRef, SeriesRef(serverID: config.id, seriesID: "5"))
        XCTAssertEqual(entries[1].progress ?? 0, 0.15, accuracy: 0.001)
        XCTAssertTrue(entries[0].isRead)
        XCTAssertEqual(entries[1].coverURL?.absoluteString,
                       "http://kavita.local:5000/api/Image/chapter-cover?apiKey=KEY&chapterId=102")
        XCTAssertTrue(mock.lastRequest(containing: "items")?.url?.absoluteString.contains("readingListId=3") == true)
        XCTAssertEqual(ReadingListEntry.resumeEntry(in: entries)?.itemID, "21")
        XCTAssertEqual(ReadingListEntry.resumeLabel(in: entries), "Continue")
    }

    func testResumeRules() {
        let ref = SeriesRef(serverID: config.id, seriesID: "1")
        func entry(_ id: String, read: Int) -> ReadingListEntry {
            ReadingListEntry(itemID: id, order: 0, seriesRef: ref, seriesTitle: "S", chapterID: id, title: id,
                             pageCount: 10, pagesRead: read)
        }
        XCTAssertNil(ReadingListEntry.resumeEntry(in: []))
        XCTAssertEqual(ReadingListEntry.resumeLabel(in: [entry("a", read: 0)]), "Start")
        XCTAssertEqual(ReadingListEntry.resumeLabel(in: [entry("a", read: 10), entry("b", read: 0)]), "Continue")
        let done = [entry("a", read: 10), entry("b", read: 10)]
        XCTAssertEqual(ReadingListEntry.resumeLabel(in: done), "Read Again")
        XCTAssertEqual(ReadingListEntry.resumeEntry(in: done)?.itemID, "a")
        XCTAssertNil(entry("a", read: 0).progress)
        XCTAssertNil(entry("a", read: 10).progress)
    }

    func testListsSortByTitleNaturally() {
        let id = config.id
        let items = ["Arc 10", "arc 2", "Beta"].enumerated().map {
            ServerCollection(serverID: id, kind: .collection, collectionID: String($0.offset), title: $0.element)
        }
        XCTAssertEqual(ServerCollection.sorted(items.reversed()).map(\.title), ["arc 2", "Arc 10", "Beta"])
    }

    func testDemoServerListsOnlyForKavitaKind() async throws {
        let kavita = SampleLibraryServer(config: ServerConfig(kind: .kavita, name: "Demo Kavita", baseURL: config.baseURL),
                                         latency: .zero)
        let suwayomi = SampleLibraryServer(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: config.baseURL),
                                           latency: .zero)
        XCTAssertEqual(suwayomi.collectionSupport, [])
        let none = try await suwayomi.collections(.collection)
        XCTAssertTrue(none.isEmpty)

        let lists = try await kavita.collections(.readingList)
        XCTAssertEqual(lists.map(\.collectionID), ["rl-1", "rl-2"])
        let entries = try await kavita.readingListEntries(lists[0])
        XCTAssertEqual(entries.map(\.chapterID), ["1-1", "2-1", "3-1", "1-2"])
        XCTAssertEqual(ReadingListEntry.resumeLabel(in: entries), "Start")
        let empty = try await kavita.readingListEntries(lists[1])
        XCTAssertTrue(empty.isEmpty)

        let harbor = try await kavita.collections(.collection)
        let page = try await kavita.series(in: harbor[0], page: 1, pageSize: 5)
        XCTAssertEqual(page.items.map(\.ref.seriesID), ["2", "10", "18", "26", "34"])
        XCTAssertTrue(page.hasMore)
        let filter = try await kavita.collections(.smartFilter)
        let fifth = try await kavita.series(in: filter[0], page: 1, pageSize: 100)
        XCTAssertEqual(fifth.items.count, 18)
        XCTAssertFalse(fifth.hasMore)

        // Progress shows up in the list.
        let chapter = Chapter(id: "1-1", seriesRef: entries[0].seriesRef, title: "Chapter 1", number: 1, pageCount: 20)
        try await kavita.saveProgress(chapter: chapter, libraryID: nil, page: 19, completed: true)
        let after = try await kavita.readingListEntries(lists[0])
        XCTAssertTrue(after[0].isRead)
        XCTAssertEqual(ReadingListEntry.resumeEntry(in: after)?.chapterID, "2-1")
    }
}
