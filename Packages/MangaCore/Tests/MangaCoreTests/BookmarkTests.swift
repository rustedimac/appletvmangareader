import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class BookmarkTests: XCTestCase {
    let kavita = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local")!)
    let suwayomi = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local")!)

    func series(_ id: String, on server: ServerConfig? = nil) -> SeriesSummary {
        SeriesSummary(ref: SeriesRef(serverID: (server ?? kavita).id, seriesID: id), title: "Series \(id)", coverURL: nil)
    }

    func chapter(_ id: String, number: Double, in s: SeriesSummary, volume: String? = "10") -> Chapter {
        Chapter(id: id, seriesRef: s.ref, volumeID: volume, title: "Chapter \(Int(number))", number: number, pageCount: 20)
    }

    // MARK: AppState

    func testBookmarksArePerProfileAndOrdered() {
        var s = AppState.initial()
        s.addServer(kavita)
        let a = s.profiles[0].id
        let b = s.addProfile(name: "B").id
        let one = series("1")
        let t0 = Date(timeIntervalSince1970: 1000)
        s.setBookmark(Bookmark(series: one, chapter: chapter("c2", number: 2, in: one), page: 3, createdAt: t0), true, profile: a)
        s.setBookmark(Bookmark(series: one, chapter: chapter("c1", number: 1, in: one), page: 7, createdAt: t0.addingTimeInterval(10)), true, profile: a)
        s.setBookmark(Bookmark(series: one, chapter: chapter("c1", number: 1, in: one), page: 2, createdAt: t0.addingTimeInterval(20)), true, profile: a)

        XCTAssertEqual(s.bookmarks(for: one.ref, profile: a).map { "\($0.chapterID):\($0.page)" }, ["c1:2", "c1:7", "c2:3"])
        XCTAssertEqual(s.bookmarks(profile: a).map(\.page), [2, 7, 3], "newest first")
        XCTAssertTrue(s.bookmarks(profile: b).isEmpty)
        XCTAssertTrue(s.isBookmarked(one.ref, chapterID: "c1", page: 7, profile: a))
        XCTAssertFalse(s.isBookmarked(one.ref, chapterID: "c1", page: 7, profile: b))
    }

    func testAddingTwiceKeepsOneAndRemoving() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let one = series("1")
        let c = chapter("c1", number: 1, in: one)
        let first = Bookmark(series: one, chapter: c, page: 0, createdAt: Date(timeIntervalSince1970: 1))
        s.setBookmark(first, true, profile: p)
        s.setBookmark(Bookmark(series: one, chapter: c, page: 0, createdAt: Date(timeIntervalSince1970: 2)), true, profile: p)
        XCTAssertEqual(s.bookmarks(profile: p).count, 1)
        XCTAssertEqual(s.bookmarks(profile: p).first?.createdAt, first.createdAt)
        s.setBookmark(first, false, profile: p)
        XCTAssertTrue(s.bookmarks(profile: p).isEmpty)
    }

    func testRemovingServerDropsItsBookmarks() {
        var s = AppState.initial()
        s.addServer(kavita)
        s.addServer(suwayomi)
        let p = s.profiles[0].id
        let k = series("1"), w = series("1", on: suwayomi)
        s.setBookmark(Bookmark(series: k, chapter: chapter("c", number: 1, in: k), page: 0), true, profile: p)
        s.setBookmark(Bookmark(series: w, chapter: chapter("c", number: 1, in: w), page: 0), true, profile: p)
        s.removeServer(kavita.id)
        XCTAssertEqual(s.bookmarks(profile: p).map(\.series.ref.serverID), [suwayomi.id])
    }

    func testUpdateChaptersFillsTitlesAndPositions() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let one = series("1")
        s.setBookmark(Bookmark(series: one, chapterID: "c9", chapterTitle: "", page: 1), true, profile: p)
        let detail = SeriesDetail(summary: one, synopsis: nil, authors: [], genres: [], status: nil,
                                  chapters: [chapter("c9", number: 4, in: one, volume: "77")])
        s.updateBookmarkChapters(from: detail, profile: p)
        let b = try! XCTUnwrap(s.bookmarks(profile: p).first)
        XCTAssertEqual(b.chapterTitle, "Chapter 4")
        XCTAssertEqual(b.chapterNumber, 4)
        XCTAssertEqual(b.volumeID, "77")
    }

    func testOldStateWithoutBookmarksDecodes() throws {
        // ProfileData as saved before bookmarks and favorites sorting existed.
        let settings = String(decoding: try JSONEncoder().encode(ReaderSettings.default), as: UTF8.self)
        let json = #"{"serverSettings":{},"favorites":[{"series":{"ref":{"serverID":"7F1B4E1A-1111-4D7A-9C3B-3C2D1E0F9A8B","seriesID":"5"},"title":"Old"},"addedAt":700000000}],"progress":{},"defaultReaderSettings":\#(settings),"readerOverrides":{}}"#
        let data = try JSONDecoder().decode(ProfileData.self, from: Data(json.utf8))
        XCTAssertTrue(data.bookmarks.isEmpty)
        XCTAssertEqual(data.favoritesSort, .default)
        XCTAssertEqual(data.favorites.first?.series.title, "Old")
        XCTAssertNil(data.favorites.first?.latestChapterAt)
    }

    func testStateRoundTripsBookmarksAndSort() throws {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let one = series("1")
        var b = Bookmark(series: one, chapter: chapter("c1", number: 1, in: one), page: 5,
                         createdAt: Date(timeIntervalSince1970: 1234))
        b.needsUpload = false
        s.setBookmark(b, true, profile: p)
        s.setFavoritesSort(FavoritesSort(key: .latestChapter, ascending: true), profile: p)
        let store = StateStore(backing: InMemoryKeyValueStore())
        store.save(s)
        let loaded = store.load()
        XCTAssertEqual(loaded, s)
        XCTAssertEqual(loaded.favoritesSort(profile: p), FavoritesSort(key: .latestChapter, ascending: true))
        XCTAssertEqual(loaded.bookmarks(profile: p), [b])
    }

    func testNewBookmarksWaitForUpload() {
        let one = series("1")
        XCTAssertTrue(Bookmark(series: one, chapter: chapter("c", number: 1, in: one), page: 0).needsUpload)
    }

    // MARK: Merge

    func testPageMergeTakesServerAsTruthButKeepsPendingUploads() {
        let one = series("1")
        var confirmedKept = Bookmark(series: one, chapter: chapter("c1", number: 1, in: one), page: 2)
        confirmedKept.needsUpload = false
        var confirmedGone = Bookmark(series: one, chapter: chapter("c1", number: 1, in: one), page: 9)
        confirmedGone.needsUpload = false
        let pending = Bookmark(series: one, chapter: chapter("c2", number: 2, in: one), page: 0)
        let server = [
            ServerBookmark(seriesID: "1", chapterID: "c1", volumeID: "10", page: 2),
            ServerBookmark(seriesID: "1", chapterID: "c3", volumeID: "11", page: 4, chapterTitle: "Vol 2 Ch 3"),
        ]
        let merged = BookmarkSync.merge(local: [confirmedKept, confirmedGone, pending], server: server,
                                        granularity: .page, series: { $0 == "1" ? one : nil })
        XCTAssertEqual(merged.map { "\($0.chapterID):\($0.page)" }, ["c1:2", "c3:4", "c2:0"])
        XCTAssertEqual(merged[0].chapterTitle, "Chapter 1", "local details are kept")
        XCTAssertEqual(merged[1].chapterTitle, "Vol 2 Ch 3")
        XCTAssertEqual(merged[1].volumeID, "11")
        XCTAssertFalse(merged[1].needsUpload)
        XCTAssertTrue(merged[2].needsUpload)
    }

    func testPageMergeConfirmsPendingTheServerAlreadyHas() {
        let one = series("1")
        let pending = Bookmark(series: one, chapter: chapter("c1", number: 1, in: one), page: 2)
        let merged = BookmarkSync.merge(local: [pending],
                                        server: [ServerBookmark(seriesID: "1", chapterID: "c1", page: 2)],
                                        granularity: .page)
        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].needsUpload)
    }

    func testMergeSkipsServerBookmarksWithUnknownSeries() {
        let merged = BookmarkSync.merge(local: [], server: [ServerBookmark(seriesID: "404", chapterID: "c", page: 0)],
                                        granularity: .page)
        XCTAssertTrue(merged.isEmpty)
    }

    func testChapterMergeKeepsPagesInBookmarkedChapters() {
        let one = series("1", on: suwayomi)
        var page3 = Bookmark(series: one, chapter: chapter("10", number: 1, in: one, volume: nil), page: 3)
        page3.needsUpload = false
        var page8 = Bookmark(series: one, chapter: chapter("10", number: 1, in: one, volume: nil), page: 8)
        page8.needsUpload = false
        var unbookmarkedElsewhere = Bookmark(series: one, chapter: chapter("11", number: 2, in: one, volume: nil), page: 1)
        unbookmarkedElsewhere.needsUpload = false
        let server = [
            ServerBookmark(seriesID: "1", chapterID: "10", page: nil),
            ServerBookmark(seriesID: "1", chapterID: "12", page: nil, chapterTitle: "Ch. 3", series: one),
        ]
        let merged = BookmarkSync.merge(local: [page3, page8, unbookmarkedElsewhere], server: server, granularity: .chapter)
        XCTAssertEqual(merged.map { "\($0.chapterID):\($0.page)" }, ["10:3", "10:8", "12:0"])
        XCTAssertEqual(merged[2].chapterTitle, "Ch. 3")
    }

    func testChapterSendRules() {
        let one = series("1", on: suwayomi)
        let c = chapter("10", number: 1, in: one, volume: nil)
        var a = Bookmark(series: one, chapter: c, page: 1)
        a.needsUpload = false
        let b = Bookmark(series: one, chapter: c, page: 5)
        XCTAssertFalse(BookmarkSync.shouldSendAddition(of: b, existing: [a], granularity: .chapter),
                       "chapter already bookmarked on the server")
        XCTAssertTrue(BookmarkSync.shouldSendAddition(of: b, existing: [], granularity: .chapter))
        XCTAssertTrue(BookmarkSync.shouldSendAddition(of: b, existing: [a], granularity: .page))
        XCTAssertFalse(BookmarkSync.shouldSendRemoval(of: a, remaining: [b], granularity: .chapter),
                       "another page still bookmarks the chapter")
        XCTAssertTrue(BookmarkSync.shouldSendRemoval(of: a, remaining: [], granularity: .chapter))
        XCTAssertTrue(BookmarkSync.shouldSendRemoval(of: a, remaining: [b], granularity: .page))
    }

    // MARK: Kavita

    func kavitaClient(_ mock: MockTransport) -> KavitaClient {
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"john","token":"jwt-1"}"#)
        return KavitaClient(config: kavita, apiKey: "KEY", transport: mock)
    }

    func testKavitaSeriesBookmarks() async throws {
        let mock = MockTransport()
        let client = kavitaClient(mock)
        mock.on("GET", "api/Reader/series-bookmarks", body: #"[{"id":1,"page":4,"volumeId":10,"seriesId":5,"chapterId":42,"imageOffset":0,"chapterTitle":""}]"#)
        let items = try await client.bookmarks(seriesID: "5")
        XCTAssertEqual(items, [ServerBookmark(seriesID: "5", chapterID: "42", volumeID: "10", page: 4)])
        let url = try XCTUnwrap(mock.lastRequest(containing: "series-bookmarks")?.url?.absoluteString)
        XCTAssertTrue(url.contains("seriesId=5"), url)
        XCTAssertEqual(mock.lastRequest(containing: "series-bookmarks")?.value(forHTTPHeaderField: "x-api-key"), "KEY")
    }

    func testKavitaAllBookmarksIncludeSeries() async throws {
        let mock = MockTransport()
        let client = kavitaClient(mock)
        mock.on("POST", "api/Reader/all-bookmarks", body: #"[{"id":1,"page":0,"volumeId":10,"seriesId":5,"chapterId":42,"series":{"id":5,"name":"Vinland Saga","libraryId":2}}]"#)
        let items = try await client.allBookmarks()
        XCTAssertEqual(items.first?.series?.title, "Vinland Saga")
        XCTAssertEqual(items.first?.series?.libraryID, "2")
        XCTAssertEqual(items.first?.series?.ref, SeriesRef(serverID: kavita.id, seriesID: "5"))
    }

    func testKavitaSetBookmarkPostsDto() async throws {
        let mock = MockTransport()
        let client = kavitaClient(mock)
        mock.on("POST", "api/Reader/bookmark", body: "")
        mock.on("POST", "api/Reader/unbookmark", body: "")
        let one = series("5")
        let b = Bookmark(series: one, chapter: chapter("42", number: 1, in: one, volume: "10"), page: 4)
        try await client.setBookmark(true, b)
        let body = jsonBody(mock.lastRequest(containing: "api/Reader/bookmark"))
        XCTAssertEqual(body["page"] as? Int, 4)
        XCTAssertEqual(body["chapterId"] as? Int, 42)
        XCTAssertEqual(body["volumeId"] as? Int, 10)
        XCTAssertEqual(body["seriesId"] as? Int, 5)
        try await client.setBookmark(false, b)
        XCTAssertNotNil(mock.lastRequest(containing: "api/Reader/unbookmark"))
    }

    func testKavitaBookmarkWithoutVolumeFails() async {
        let mock = MockTransport()
        let client = kavitaClient(mock)
        let one = series("5")
        do {
            try await client.setBookmark(true, Bookmark(series: one, chapterID: "42", chapterTitle: "", page: 0))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MangaError, .notFound)
        }
    }

    func testKavitaDetailHasLatestChapterDate() async throws {
        let mock = MockTransport()
        let client = kavitaClient(mock)
        mock.on("GET", "api/Series/5", body: #"{"id":5,"name":"Vinland Saga","libraryId":1,"lastChapterAdded":"2024-06-01T10:00:00"}"#)
        mock.on("GET", "api/Series/volumes", body: "[]")
        mock.on("GET", "api/Series/metadata", body: "{}")
        let detail = try await client.seriesDetail("5")
        let date = try XCTUnwrap(detail.latestChapterDate)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: date), 2024)

        mock.on("GET", "api/Series/6", body: #"{"id":6,"name":"New","lastChapterAdded":"0001-01-01T00:00:00"}"#)
        let never = try await client.seriesDetail("6")
        XCTAssertNil(never.latestChapterAt)
    }

    // MARK: Suwayomi

    func testSuwayomiSeriesBookmarksAreChapters() async throws {
        let mock = MockTransport()
        let client = SuwayomiClient(config: suwayomi, username: nil, password: nil, transport: mock)
        mock.onGraphQL("isBookmarked", body: #"{"data":{"manga":{"chapters":{"nodes":[{"id":10,"name":"Ch. 1","isBookmarked":true},{"id":11,"name":"Ch. 2","isBookmarked":false}]}}}}"#)
        let items = try await client.bookmarks(seriesID: "3")
        XCTAssertEqual(items, [ServerBookmark(seriesID: "3", chapterID: "10", page: nil, chapterTitle: "Ch. 1")])
        XCTAssertEqual(client.bookmarkGranularity, .chapter)
    }

    func testSuwayomiAllBookmarks() async throws {
        let mock = MockTransport()
        let client = SuwayomiClient(config: suwayomi, username: nil, password: nil, transport: mock)
        mock.onGraphQL("isBookmarked: {equalTo: true}", body: #"{"data":{"chapters":{"nodes":[{"id":10,"name":"Ch. 1","manga":{"id":3,"title":"Sky Garden","thumbnailUrl":"/api/v1/manga/3/thumbnail","unreadCount":2,"inLibrary":true}}]}}}"#)
        let items = try await client.allBookmarks()
        XCTAssertEqual(items.first?.series?.title, "Sky Garden")
        XCTAssertEqual(items.first?.seriesID, "3")
        XCTAssertEqual(items.first?.chapterID, "10")
    }

    func testSuwayomiSetBookmarkPatchesChapter() async throws {
        let mock = MockTransport()
        let client = SuwayomiClient(config: suwayomi, username: nil, password: nil, transport: mock)
        mock.onGraphQL("updateChapter", body: #"{"data":{"updateChapter":{"clientMutationId":null}}}"#)
        let one = series("3", on: suwayomi)
        try await client.setBookmark(false, Bookmark(series: one, chapterID: "10", chapterTitle: "", page: 6))
        let body = jsonBody(mock.lastRequest(containing: "updateChapter"))
        XCTAssertTrue((body["query"] as? String)?.contains("isBookmarked: $bookmarked") == true)
        let vars = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(vars["id"] as? Int, 10)
        XCTAssertEqual(vars["bookmarked"] as? Bool, false)
    }
}
