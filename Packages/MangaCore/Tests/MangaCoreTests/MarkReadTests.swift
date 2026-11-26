import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Per-chapter "Mark as Read" and "Mark Previous as Read": each client,
/// local progress, and the optimistic detail update.
final class MarkReadTests: XCTestCase {
    let kavitaConfig = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local:5000")!)
    let suwayomiConfig = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local:4567/")!)

    func testKavitaMarkChaptersReadUsesMarkMultipleRead() async throws {
        let mock = MockTransport()
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"john","token":"jwt-1"}"#)
        mock.on("POST", "api/Reader/mark-multiple-read", body: "")
        let client = KavitaClient(config: kavitaConfig, apiKey: "KEY", transport: mock)
        let ref = SeriesRef(serverID: kavitaConfig.id, seriesID: "5")
        try await client.markRead(chapters: [
            Chapter(id: "77", seriesRef: ref, volumeID: "3", title: "1", number: 1, pageCount: 20),
            Chapter(id: "78", seriesRef: ref, volumeID: "3", title: "2", number: 2, pageCount: 20),
        ], libraryID: nil)
        let body = jsonBody(mock.lastRequest(containing: "mark-multiple-read"))
        XCTAssertEqual(body["seriesId"] as? Int, 5)
        XCTAssertEqual(body["chapterIds"] as? [Int], [77, 78])
    }

    func testKavitaMarkReadEmptyDoesNothing() async throws {
        let mock = MockTransport()
        let client = KavitaClient(config: kavitaConfig, apiKey: "KEY", transport: mock)
        try await client.markRead(chapters: [], libraryID: "1")
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testSuwayomiMarkChaptersRead() async throws {
        let mock = MockTransport()
        let client = SuwayomiClient(config: suwayomiConfig, username: nil, password: nil, transport: mock)
        mock.onGraphQL("updateChapters", body: #"{"data":{"updateChapters":{"clientMutationId":null}}}"#)
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "9")
        try await client.markRead(chapters: [
            Chapter(id: "11", seriesRef: ref, title: "1", number: 1, pageCount: 10),
        ], libraryID: nil)
        let body = jsonBody(mock.lastRequest(containing: "updateChapters"))
        XCTAssertTrue((body["query"] as? String ?? "").contains("isRead: true"))
        XCTAssertEqual((body["variables"] as? [String: Any])?["ids"] as? [Int], [11])
    }

    func testDefaultMarkReadSavesCompletedProgress() async throws {
        let server = SampleLibraryServer(config: kavitaConfig, seriesCount: 4, latency: .zero)
        var d = try await server.seriesDetail("2")
        XCTAssertFalse(d.chapters[1].isRead)
        try await server.markRead(chapters: [d.chapters[1]], libraryID: nil)
        d = try await server.seriesDetail("2")
        XCTAssertEqual(d.chapters[0].readState, .unread)
        XCTAssertEqual(d.chapters[1].readState, .read)
    }

    // MARK: Local progress

    func detail(_ ref: SeriesRef, read: [String] = []) -> SeriesDetail {
        SeriesDetail(summary: SeriesSummary(ref: ref, title: "X", coverURL: nil),
                     synopsis: nil, authors: [], genres: [], status: nil,
                     chapters: ["1", "2", "3"].enumerated().map { i, id in
                         Chapter(id: id, seriesRef: ref, title: id, number: Double(i + 1), pageCount: 20,
                                 isRead: read.contains(id))
                     })
    }

    func testLocalMarkReadKeepsTheResumePosition() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "3")
        s.recordProgress(ref, chapterID: "1", page: 7, completed: false, profile: p)
        s.markRead(ref, chapterIDs: ["2", "3"], profile: p)
        let progress = s.progress(ref, profile: p)
        XCTAssertEqual(progress?.chapterID, "1")
        XCTAssertEqual(progress?.page, 7)
        XCTAssertEqual(progress?.readChapterIDs, ["2", "3"])
        let merged = s.applyingLocalProgress(to: detail(ref), profile: p)
        XCTAssertEqual(merged.chapters.map(\.isRead), [false, true, true])
    }

    func testLocalMarkReadUndoesAnEarlierUnread() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "3")
        s.markUnread(ref, chapterIDs: ["1"], profile: p)
        s.markRead(ref, chapterIDs: ["1"], profile: p)
        XCTAssertEqual(s.progress(ref, profile: p)?.unreadChapterIDs, [])
        XCTAssertTrue(s.applyingLocalProgress(to: detail(ref), profile: p).chapters[0].isRead)
    }

    func testLocalMarkReadAfterSeriesUnread() {
        var s = AppState.initial()
        let p = s.profiles[0].id
        let ref = SeriesRef(serverID: suwayomiConfig.id, seriesID: "3")
        s.markSeriesUnread(ref, profile: p)
        s.markRead(ref, chapterIDs: ["2"], profile: p)
        let merged = s.applyingLocalProgress(to: detail(ref, read: ["1", "2", "3"]), profile: p)
        XCTAssertEqual(merged.chapters.map(\.isRead), [false, true, false])
    }

    // MARK: Detail helpers

    func testMarkingReadAndChaptersBefore() {
        let ref = SeriesRef(serverID: kavitaConfig.id, seriesID: "1")
        let d = detail(ref, read: ["1"])
        XCTAssertEqual(d.markingRead(["2"]).chapters.map(\.isRead), [true, true, false])
        XCTAssertEqual(d.chapters(before: d.chapters[2]).map(\.id), ["1", "2"])
        XCTAssertEqual(d.chapters(before: d.chapters[0]), [])
        XCTAssertEqual(d.markingRead(["2"]).continueAction?.chapter.id, "3")
    }
}
