import XCTest
@testable import MangaCore

final class DeepLinkTests: XCTestCase {
    let ref = SeriesRef(serverID: UUID(), seriesID: "42")
    let profile = UUID()

    func testSeriesLinkRoundTrips() {
        let link = DeepLink.series(ref, profile: profile)
        XCTAssertEqual(link.url.scheme, "mangareader")
        XCTAssertEqual(link.url.host, "series")
        XCTAssertEqual(DeepLink(url: link.url), link)
    }

    func testReadLinkRoundTrips() {
        let link = DeepLink.read(ref, chapterID: "ch 7/b", page: 12, profile: profile)
        XCTAssertEqual(DeepLink(url: link.url), link)
        let noPage = DeepLink.read(ref, chapterID: "7", page: nil, profile: nil)
        XCTAssertEqual(DeepLink(url: noPage.url), noPage)
    }

    func testRejectsBadLinks() {
        let server = ref.serverID.uuidString
        XCTAssertNil(DeepLink(url: URL(string: "https://series?server=\(server)&series=1")!))
        XCTAssertNil(DeepLink(url: URL(string: "mangareader://series?server=nope&series=1")!))
        XCTAssertNil(DeepLink(url: URL(string: "mangareader://series?server=\(server)")!))
        XCTAssertNil(DeepLink(url: URL(string: "mangareader://read?server=\(server)&series=1")!))
        XCTAssertNil(DeepLink(url: URL(string: "mangareader://other?server=\(server)&series=1")!))
    }

    func testNegativePageClampsToZero() {
        let url = URL(string: "mangareader://read?server=\(ref.serverID.uuidString)&series=1&chapter=c&page=-3")!
        XCTAssertEqual(DeepLink(url: url), .read(SeriesRef(serverID: ref.serverID, seriesID: "1"),
                                                 chapterID: "c", page: 0, profile: nil))
    }
}

final class TopShelfSnapshotTests: XCTestCase {
    let kavita = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local")!)

    func summary(_ id: String, unread: Int? = nil, cover: Bool = true) -> SeriesSummary {
        SeriesSummary(ref: SeriesRef(serverID: kavita.id, seriesID: id), title: "Series \(id)",
                      coverURL: cover ? URL(string: "http://kavita.local/api/Image/series-cover?seriesId=\(id)&apiKey=SECRET") : nil,
                      unreadCount: unread, libraryID: "1")
    }

    func read(_ s: inout AppState, _ series: SeriesSummary, chapter: String, page: Int, at t: TimeInterval) {
        let p = s.activeProfile!.id
        s.noteRecentSeries(series, profile: p)
        s.recordProgress(series.ref, chapterID: chapter, page: page, completed: false, profile: p,
                         now: Date(timeIntervalSince1970: t))
    }

    func testEmptyStateHasNoSections() {
        var s = AppState.initial()
        s.addServer(kavita)
        XCTAssertTrue(TopShelfSnapshot.make(from: s).sections.isEmpty)
    }

    func testContinueReadingIsNewestFirstAndLinksIntoTheReader() throws {
        var s = AppState.initial()
        s.addServer(kavita)
        let profile = s.activeProfile!.id
        read(&s, summary("1"), chapter: "c1", page: 3, at: 100)
        read(&s, summary("2"), chapter: "c9", page: 0, at: 200)
        let snap = TopShelfSnapshot.make(from: s)
        XCTAssertEqual(snap.profileID, profile)
        let section = try XCTUnwrap(snap.sections.first)
        XCTAssertEqual(section.kind, .continueReading)
        XCTAssertEqual(section.items.map(\.title), ["Series 2", "Series 1"])
        XCTAssertEqual(DeepLink(url: section.items[1].playURL),
                       .read(summary("1").ref, chapterID: "c1", page: 3, profile: profile))
        XCTAssertEqual(DeepLink(url: section.items[1].displayURL), .series(summary("1").ref, profile: profile))
    }

    func testFavoritesWithNewChaptersComeFirstAndSkipContinueReading() throws {
        var s = AppState.initial()
        s.addServer(kavita)
        let p = s.activeProfile!.id
        s.setFavorite(summary("1"), true, profile: p, now: Date(timeIntervalSince1970: 1))
        s.setFavorite(summary("2", unread: 0), true, profile: p, now: Date(timeIntervalSince1970: 3))
        s.setFavorite(summary("3", unread: 2), true, profile: p, now: Date(timeIntervalSince1970: 2))
        s.setFavorite(summary("4"), true, profile: p, now: Date(timeIntervalSince1970: 4))
        read(&s, summary("4"), chapter: "x", page: 1, at: 10)
        // A refresh (series detail) found 5 unread chapters.
        let chapters = (1...5).map { Chapter(id: "c\($0)", seriesRef: summary("1").ref, title: "\($0)", number: Double($0), pageCount: 10) }
        let detail = SeriesDetail(summary: summary("1"), synopsis: nil, authors: [], genres: [], status: nil, chapters: chapters)
        s.updateFavorite(from: detail, profile: p)

        let snap = TopShelfSnapshot.make(from: s)
        let favorites = try XCTUnwrap(snap.sections.first { $0.kind == .favorites })
        XCTAssertEqual(favorites.items.map(\.title), ["Series 1 · 5 new", "Series 3 · 2 new", "Series 2"])
        // A favorite never read opens its series page on Play.
        XCTAssertEqual(DeepLink(url: favorites.items[2].playURL), .series(summary("2").ref, profile: p))
        XCTAssertEqual(snap.sections.first?.kind, .continueReading)
    }

    func testFollowsActiveProfile() {
        var s = AppState.initial()
        s.addServer(kavita)
        let a = s.activeProfile!.id
        s.setFavorite(summary("1"), true, profile: a)
        let b = s.addProfile(name: "B").id
        s.setActiveProfile(b)
        XCTAssertTrue(TopShelfSnapshot.make(from: s).sections.isEmpty)
        s.setActiveProfile(a)
        XCTAssertEqual(TopShelfSnapshot.make(from: s).sections.count, 1)
    }

    func testContentFilterHidesItemsAndFailsClosed() throws {
        var s = AppState.initial()
        s.addServer(kavita)
        let p = s.activeProfile!.id
        read(&s, summary("1"), chapter: "c", page: 0, at: 1)
        read(&s, summary("2"), chapter: "c", page: 0, at: 2)
        s.setFavorite(summary("3"), true, profile: p)
        s.setFavorite(summary("4"), true, profile: p)
        s.setContentFilter(ContentFilter(hiddenGenres: ["Horror"]), profile: p)

        // Series 2 and 4 are hidden on this server.
        let snap = TopShelfSnapshot.make(from: s, hidden: [kavita.id: ["2", "4"]])
        XCTAssertEqual(snap.sections.flatMap(\.items).map(\.title), ["Series 1", "Series 3"])
        // Hidden ids not loaded yet (offline): nothing from that server.
        XCTAssertTrue(TopShelfSnapshot.make(from: s).sections.isEmpty)
        // No filter: everything shows without hidden ids.
        s.setContentFilter(.none, profile: p)
        XCTAssertEqual(TopShelfSnapshot.make(from: s).sections.flatMap(\.items).count, 4)
    }

    func testUnimportedLibraryIsLeftOut() {
        var s = AppState.initial()
        s.addServer(kavita)
        let p = s.activeProfile!.id
        read(&s, summary("1"), chapter: "c", page: 0, at: 1)
        s.setFavorite(summary("2"), true, profile: p)
        s.setSelectedCategories(["9"], profile: p, server: kavita.id)
        XCTAssertTrue(TopShelfSnapshot.make(from: s).sections.isEmpty)
    }

    func testPrivateProfileShowsNothing() {
        var s = AppState.initial()
        s.addServer(kavita)
        read(&s, summary("1"), chapter: "c", page: 0, at: 1)
        let snap = TopShelfSnapshot.make(from: s, isPrivate: true)
        XCTAssertTrue(snap.sections.isEmpty)
        XCTAssertEqual(snap.profileID, s.activeProfile!.id)
    }

    func testRemovedServerDropsItems() {
        var s = AppState.initial()
        s.addServer(kavita)
        read(&s, summary("1"), chapter: "c", page: 0, at: 1)
        s.removeServer(kavita.id)
        XCTAssertTrue(TopShelfSnapshot.make(from: s).sections.isEmpty)
        XCTAssertEqual(s.profileData[s.activeProfile!.id.uuidString]?.recentSeries?.count, 0)
    }

    func testResetProgressLeavesContinueReading() {
        var s = AppState.initial()
        s.addServer(kavita)
        read(&s, summary("1"), chapter: "", page: 0, at: 1)
        XCTAssertTrue(s.continueReading(profile: s.activeProfile!.id).isEmpty)
    }

    func testCoverFileNamesHideTheAPIKey() {
        let a = TopShelfSnapshot.coverFileName(for: URL(string: "http://k/api/Image/series-cover?seriesId=1&apiKey=AAA")!)
        let b = TopShelfSnapshot.coverFileName(for: URL(string: "http://k/api/Image/series-cover?seriesId=1&apiKey=BBB")!)
        let c = TopShelfSnapshot.coverFileName(for: URL(string: "http://k/api/Image/series-cover?seriesId=2&apiKey=AAA")!)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertFalse(a.contains("AAA"))
        XCTAssertTrue(a.hasSuffix(".jpg"))
    }

    func testRecentSeriesIsCapped() {
        var s = AppState.initial()
        s.addServer(kavita)
        for i in 0..<(AppState.recentSeriesLimit + 15) {
            read(&s, summary("\(i)"), chapter: "c", page: 0, at: TimeInterval(i))
        }
        let recent = s.profileData[s.activeProfile!.id.uuidString]?.recentSeries ?? [:]
        XCTAssertLessThanOrEqual(recent.count, AppState.recentSeriesLimit + 1)
        XCTAssertNotNil(recent[summary("\(AppState.recentSeriesLimit + 14)").ref.storageKey])
    }

    func testNoteRecentSeriesKeepsKnownFields() {
        var s = AppState.initial()
        let p = s.activeProfile!.id
        s.noteRecentSeries(summary("1"), profile: p)
        var thin = summary("1", cover: false)
        thin.libraryID = nil
        s.noteRecentSeries(thin, profile: p)
        let kept = s.knownSummary(thin.ref, profile: p)
        XCTAssertNotNil(kept?.coverURL)
        XCTAssertEqual(kept?.libraryID, "1")
    }

    func testOldStateWithoutNewFieldsDecodes() throws {
        let json = #"{"version":1,"profiles":[{"id":"8E3A2C4B-1F0D-4C55-9C1E-2B7A5D9E0F11","name":"Me","symbol":"person.fill","colorIndex":0}],"servers":[],"profileData":{"8E3A2C4B-1F0D-4C55-9C1E-2B7A5D9E0F11":{"serverSettings":{},"favorites":[],"progress":{},"defaultReaderSettings":\#(String(data: try JSONEncoder().encode(ReaderSettings.default), encoding: .utf8)!),"readerOverrides":{}}}}"#
        let s = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        XCTAssertNil(s.rememberedProfileID)
        XCTAssertNil(s.profileData.values.first?.recentSeries)
    }

    func testStoreSkipsUnchangedWritesAndPrunesCovers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TopShelfStore(directory: dir)
        var s = AppState.initial()
        s.addServer(kavita)
        read(&s, summary("1"), chapter: "c", page: 0, at: 1)
        let snap = TopShelfSnapshot.make(from: s)
        XCTAssertTrue(try store.save(snap))
        XCTAssertFalse(try store.save(snap))
        XCTAssertEqual(store.load(), snap)

        let file = try XCTUnwrap(snap.covers.first?.file)
        try store.saveCover(Data([1, 2, 3]), file: file)
        try store.saveCover(Data([4]), file: "stale.jpg")
        store.pruneCovers(keeping: [file])
        XCTAssertTrue(store.hasCover(file))
        XCTAssertFalse(store.hasCover("stale.jpg"))
    }
}
