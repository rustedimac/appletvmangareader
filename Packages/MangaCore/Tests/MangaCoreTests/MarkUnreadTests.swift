import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// "Mark as Unread" for chapters and whole series: both clients, local
/// progress, and the optimistic detail update.
final class MarkUnreadTests: XCTestCase {
    let kavitaConfig = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
    let suwayomiConfig = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local:4567/")!)

    // MARK: Kavita

    func kavita() -> (KavitaClient, MockTransport) {
        let mock = MockTransport()
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"john","token":"jwt-1"}"#)
        return (KavitaClient(config: kavitaConfig, apiKey: "KEY", transport: mock), mock)
    }

    func testKavitaMarkChaptersUnread() async throws {
        let (client, mock) = kavita()
        mock.on("POST", "api/Reader/mark-multiple-unread", body: "")
        let ref = SeriesRef(serverID: kavitaConfig.id, seriesID: "5")
        let chapters = [
            Chapter(id: "77", seriesRef: ref, volumeID: "3", title: "1", number: 1, pageCount: 20),
            Chapter(id: "78", seriesRef: ref, volumeID: "3", title: "2", number: 2, pageCount: 20),
        ]
        try await client.markUnread(chapters: chapters)
        let request = mock.lastRequest(containing: "mark-multiple-unread")
        // Kavita calls carry the auth key, not a JWT (see PROGRESS_SYNC.md).
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "KEY")
        let body = jsonBody(request)
        XCTAssertEqual(body["seriesId"] as? Int, 5)
        XCTAssertEqual(body["chapterIds"] as? [Int], [77, 78])
        XCTAssertEqual(body["volumeIds"] as? [Int], [])
    }

    func testKavitaMarkChaptersUnreadEmptyDoesNothing() async throws {
        let (client, mock) = kavita()
        try await client.markUnread(chapters: [])
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testKavitaMarkSeriesUnread() async throws {
        let (client, mock) = kavita()
        mock.on("POST", "api/Reader/mark-unread", body: "")
        try await client.markSeriesUnread("42")
        let body = jsonBody(mock.lastRequest(containing: "api/Reader/mark-unread"))
        XCTAssertEqual(body["seriesId"] as? Int, 42)
    }

    func testKavitaMarkUnreadSurfacesHTTPErrors() async {
        let (client, mock) = kavita()
        mock.on("POST", "api/Reader/mark-unread", status: 400, body: "nope")
        do {
            try await client.markSeriesUnread("42")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MangaError, .http(status: 400, body: "nope"))
        }
    }

    // MARK: Suwayomi

    func testSuwayomiMarkChaptersUnread() async throws {
        let mock = MockTransport()
        let client = SuwayomiClient(config: suwayomiConfig, username: nil, password: nil, transport: mock)
        mock.onGraphQL("updateChapters", body: #"{"data":{"updateChapters":{"clientMutationId":null}}}"#)
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "9")
        try await client.markUnread(chapters: [
            Chapter(id: "11", seriesRef: ref, title: "1", number: 1, pageCount: 10),
            Chapter(id: "12", seriesRef: ref, title: "2", number: 2, pageCount: 10),
        ])
        let body = jsonBody(mock.lastRequest(containing: "updateChapters"))
        let query = body["query"] as? String ?? ""
        XCTAssertTrue(query.contains("isRead: false"))
        XCTAssertTrue(query.contains("lastPageRead: 0"))
        XCTAssertEqual((body["variables"] as? [String: Any])?["ids"] as? [Int], [11, 12])
    }

    func testSuwayomiMarkSeriesUnreadUpdatesEveryChapter() async throws {
        let mock = MockTransport()
        let client = SuwayomiClient(config: suwayomiConfig, username: nil, password: nil, transport: mock)
        mock.onGraphQL("updateChapters", body: #"{"data":{"updateChapters":{"clientMutationId":null}}}"#)
        mock.onGraphQL("chapters { nodes { id } }", body: #"{"data":{"manga":{"chapters":{"nodes":[{"id":3},{"id":1},{"id":2}]}}}}"#)
        try await client.markSeriesUnread("9")
        let lookup = jsonBody(mock.lastRequest(containing: "chapters { nodes { id } }"))
        XCTAssertEqual((lookup["variables"] as? [String: Any])?["id"] as? Int, 9)
        let update = jsonBody(mock.lastRequest(containing: "updateChapters"))
        XCTAssertEqual((update["variables"] as? [String: Any])?["ids"] as? [Int], [3, 1, 2])
    }

    func testSuwayomiMarkSeriesUnreadWithNoChaptersSkipsMutation() async throws {
        let mock = MockTransport()
        let client = SuwayomiClient(config: suwayomiConfig, username: nil, password: nil, transport: mock)
        mock.onGraphQL("chapters { nodes { id } }", body: #"{"data":{"manga":{"chapters":{"nodes":[]}}}}"#)
        try await client.markSeriesUnread("9")
        XCTAssertNil(mock.lastRequest(containing: "updateChapters"))
    }

    // MARK: Local progress

    func detail(_ ref: SeriesRef, read: [String] = [], pages: [String: Int] = [:]) -> SeriesDetail {
        SeriesDetail(summary: SeriesSummary(ref: ref, title: "X", coverURL: nil),
                     synopsis: nil, authors: [], genres: [], status: nil,
                     chapters: ["1", "2", "3"].enumerated().map { i, id in
                         Chapter(id: id, seriesRef: ref, title: id, number: Double(i + 1), pageCount: 20,
                                 lastPageRead: pages[id] ?? 0, isRead: read.contains(id))
                     })
    }

    func testLocalMarkChapterUnread() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "3")
        s.recordProgress(ref, chapterID: "1", page: 19, completed: true, profile: p)
        s.recordProgress(ref, chapterID: "2", page: 7, completed: false, profile: p)
        s.markUnread(ref, chapterIDs: ["1", "2"], profile: p)
        let progress = s.progress(ref, profile: p)
        XCTAssertEqual(progress?.readChapterIDs, [])
        XCTAssertEqual(progress?.page, 0)

        // The server (another profile's progress) says 1 is read and 2 is
        // started; this profile's reset wins.
        let merged = s.applyingLocalProgress(to: detail(ref, read: ["1"], pages: ["2": 7]), profile: p)
        XCTAssertEqual(merged.chapters.map(\.readState), [.unread, .unread, .unread])
    }

    func testLocalUnreadIsClearedByReadingAgain() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "3")
        s.markUnread(ref, chapterIDs: ["1"], profile: p)
        s.recordProgress(ref, chapterID: "1", page: 3, completed: false, profile: p)
        XCTAssertEqual(s.progress(ref, profile: p)?.unreadChapterIDs, [])
        let merged = s.applyingLocalProgress(to: detail(ref, read: ["1"]), profile: p)
        XCTAssertEqual(merged.chapters[0].readState, .read, "server state shows again once the chapter is reopened")
    }

    func testLocalMarkSeriesUnreadIgnoresServerUntilReadAgain() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "3")
        s.recordProgress(ref, chapterID: "1", page: 19, completed: true, profile: p)
        s.markSeriesUnread(ref, profile: p)
        let serverSaysRead = detail(ref, read: ["1", "2"], pages: ["3": 4])
        XCTAssertEqual(s.applyingLocalProgress(to: serverSaysRead, profile: p).chapters.map(\.readState),
                       [.unread, .unread, .unread])
        XCTAssertEqual(s.applyingLocalProgress(to: serverSaysRead, profile: p).continueAction?.label, "Start Reading")

        s.recordProgress(ref, chapterID: "1", page: 19, completed: true, profile: p)
        s.recordProgress(ref, chapterID: "2", page: 5, completed: false, profile: p)
        XCTAssertEqual(s.applyingLocalProgress(to: serverSaysRead, profile: p).chapters.map(\.readState),
                       [.read, .inProgress(page: 6, pageCount: 20), .unread])
    }

    func testUnreadMarksArePerProfile() {
        var s = AppState.initial()
        let a = s.profiles[0].id
        let b = s.addProfile(name: "B").id
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "3")
        s.recordProgress(ref, chapterID: "1", page: 19, completed: true, profile: a)
        s.recordProgress(ref, chapterID: "1", page: 19, completed: true, profile: b)
        s.markSeriesUnread(ref, profile: a)
        XCTAssertEqual(s.progress(ref, profile: b)?.readChapterIDs, ["1"])
        XCTAssertFalse(s.progress(ref, profile: b)?.ignoresServerProgress ?? true)
    }

    func testProgressDecodesOlderStateWithoutUnreadFields() throws {
        let json = #"{"chapterID":"5","page":2,"updatedAt":0,"readChapterIDs":["4"]}"#
        let p = try JSONDecoder().decode(SeriesProgress.self, from: Data(json.utf8))
        XCTAssertEqual(p.chapterID, "5")
        XCTAssertEqual(p.readChapterIDs, ["4"])
        XCTAssertEqual(p.unreadChapterIDs, [])
        XCTAssertFalse(p.ignoresServerProgress)
    }

    func testProgressRoundTripsAndOmitsEmptyUnreadFields() throws {
        let plain = SeriesProgress(chapterID: "1", page: 0, updatedAt: Date(timeIntervalSince1970: 0))
        let text = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(text.contains("unreadChapterIDs"))
        XCTAssertFalse(text.contains("ignoresServerProgress"))

        let marked = SeriesProgress(chapterID: "1", page: 0, updatedAt: Date(timeIntervalSince1970: 0),
                                    unreadChapterIDs: ["2"], ignoresServerProgress: true)
        let decoded = try JSONDecoder().decode(SeriesProgress.self, from: JSONEncoder().encode(marked))
        XCTAssertEqual(decoded, marked)
    }

    // MARK: Detail helpers

    func testMarkingUnreadUpdatesDetailImmediately() {
        let ref = SeriesRef(serverID: kavitaConfig.id, seriesID: "1")
        let d = detail(ref, read: ["1", "2"], pages: ["3": 4])
        XCTAssertTrue(d.hasProgress)
        XCTAssertEqual(d.markingUnread(["2"]).chapters.map(\.readState),
                       [.read, .unread, .inProgress(page: 5, pageCount: 20)])
        let all = d.markingUnread()
        XCTAssertEqual(all.chapters.map(\.readState), [.unread, .unread, .unread])
        XCTAssertFalse(all.hasProgress)
        XCTAssertEqual(all.posterUnreadCount, 3)
    }

    // MARK: Demo server

    func testDemoServerMarkUnread() async throws {
        let server = SampleLibraryServer(config: kavitaConfig, seriesCount: 4, latency: .zero)
        server.seedProgress(read: 2, inProgressPage: 5)
        var d = try await server.seriesDetail("2")
        XCTAssertEqual(d.chapters.prefix(3).map(\.readState), [.read, .read, .inProgress(page: 6, pageCount: 20)])

        try await server.markUnread(chapters: [d.chapters[0]])
        d = try await server.seriesDetail("2")
        XCTAssertEqual(d.chapters.prefix(3).map(\.readState), [.unread, .read, .inProgress(page: 6, pageCount: 20)])

        try await server.markSeriesUnread("2")
        d = try await server.seriesDetail("2")
        XCTAssertFalse(d.hasProgress)
        XCTAssertEqual(d.summary.unreadCount, SampleLibraryServer.chapterCount(for: 2))
        // Other series keep their progress.
        let other = try await server.seriesDetail("3")
        XCTAssertTrue(other.chapters[0].isRead)
    }
}
