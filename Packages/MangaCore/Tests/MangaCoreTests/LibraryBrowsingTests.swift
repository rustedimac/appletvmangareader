import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

private let serverID = UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!

private func series(_ id: String, _ title: String, unread: Int? = nil, library: String? = nil,
                    categories: [String]? = nil, pages: Int? = nil, read: Int? = nil, chapters: Int? = nil) -> SeriesSummary {
    SeriesSummary(ref: SeriesRef(serverID: serverID, seriesID: id), title: title, coverURL: nil, unreadCount: unread,
                  libraryID: library, categoryIDs: categories, pageCount: pages, pagesRead: read, chapterCount: chapters)
}

final class AlphabetIndexTests: XCTestCase {
    func testLetterForTitle() {
        XCTAssertEqual(AlphabetIndex.letter(for: "Ember Chronicles"), "E")
        XCTAssertEqual(AlphabetIndex.letter(for: "élan vital"), "E")
        XCTAssertEqual(AlphabetIndex.letter(for: "[Oneshot] Quiet Harbor"), "O")
        XCTAssertEqual(AlphabetIndex.letter(for: "\u{201C}Quoted\u{201D}"), "Q")
        XCTAssertEqual(AlphabetIndex.letter(for: "ｚｅｐｈｙｒ"), "Z", "full-width Latin folds to A–Z")
        XCTAssertEqual(AlphabetIndex.letter(for: "100 Lanterns"), "#")
        XCTAssertEqual(AlphabetIndex.letter(for: "夜の港"), "#")
        XCTAssertEqual(AlphabetIndex.letter(for: "   "), "#")
        XCTAssertEqual(AlphabetIndex.letters.count, 27)
        XCTAssertEqual(AlphabetIndex.letters.first, "#")
        XCTAssertEqual(AlphabetIndex.letters.last, "Z")
    }

    func testJumpAscending() {
        let titles = ["3 Moons", "Amber", "Birch", "Delta", "Echo"]
        XCTAssertEqual(AlphabetIndex.jump(to: "#", in: titles, hasMore: false), .index(0))
        XCTAssertEqual(AlphabetIndex.jump(to: "B", in: titles, hasMore: false), .index(2))
        XCTAssertEqual(AlphabetIndex.jump(to: "C", in: titles, hasMore: false), .index(3), "missing letter lands on the next")
        XCTAssertEqual(AlphabetIndex.jump(to: "M", in: titles, hasMore: true), .needsMore)
        XCTAssertEqual(AlphabetIndex.jump(to: "M", in: titles, hasMore: false), .index(4), "past the end lands on the last")
        XCTAssertEqual(AlphabetIndex.jump(to: "A", in: [], hasMore: false), .none)
    }

    func testJumpDescending() {
        let titles = ["Zephyr", "Willow", "Meadow", "Ember"]
        XCTAssertEqual(AlphabetIndex.jump(to: "W", in: titles, descending: true, hasMore: false), .index(1))
        XCTAssertEqual(AlphabetIndex.jump(to: "P", in: titles, descending: true, hasMore: false), .index(2))
        XCTAssertEqual(AlphabetIndex.jump(to: "B", in: titles, descending: true, hasMore: true), .needsMore)
    }
}

final class LibrarySortTests: XCTestCase {
    func testClientSideSorting() {
        let items = [series("1", "Willow 10"), series("2", "Willow 9"), series("3", "Amber")]
        XCTAssertEqual(items.sorted(by: .titleAscending).map(\.title), ["Amber", "Willow 9", "Willow 10"])
        XCTAssertEqual(items.sorted(by: .titleDescending).map(\.title), ["Willow 10", "Willow 9", "Amber"])
        let dates: [SeriesRef: Date] = [items[0].ref: Date(timeIntervalSince1970: 100), items[2].ref: Date(timeIntervalSince1970: 200)]
        XCTAssertEqual(items.sorted(by: .recentlyAdded, dates: dates).map(\.ref.seriesID), ["3", "1", "2"],
                       "newest first, undated last")
        XCTAssertTrue(LibrarySort.titleAscending.isTitleOrder)
        XCTAssertFalse(LibrarySort.recentlyRead.isTitleOrder)
    }

    func testGridDensityGrows() {
        XCTAssertLessThan(GridDensity.compact.posterWidth, GridDensity.standard.posterWidth)
        XCTAssertLessThan(GridDensity.standard.posterWidth, GridDensity.large.posterWidth)
        XCTAssertEqual(GridDensity.standard.posterWidth, 230, "matches the shelves' poster size")
    }

    func testReadingStyleAndGridOrder() {
        let base = ReaderSettings(mode: .webtoon, direction: .leftToRight, layout: .double)
        let rtl = LibraryReadingStyle.rightToLeft.apply(to: base)
        XCTAssertEqual(rtl.mode, .paged)
        XCTAssertEqual(rtl.direction, .rightToLeft)
        XCTAssertEqual(rtl.layout, .double, "other settings are kept")
        XCTAssertEqual(LibraryReadingStyle.vertical.apply(to: .default).mode, .webtoon)
        XCTAssertEqual(LibraryReadingStyle.leftToRight.apply(to: .default).direction, .leftToRight)

        XCTAssertFalse(LibraryOptions().gridIsRightToLeft)
        XCTAssertTrue(LibraryOptions(readingStyle: .rightToLeft).gridIsRightToLeft)
        XCTAssertFalse(LibraryOptions(readingStyle: .rightToLeft, gridOrder: .leftToRight).gridIsRightToLeft)
        XCTAssertTrue(LibraryOptions(readingStyle: .leftToRight, gridOrder: .rightToLeft).gridIsRightToLeft)
    }

    func testDictatedSearchLosesPunctuation() {
        XCTAssertEqual(CrossServerSearch.normalize("Ember chronicles."), "Ember chronicles")
        XCTAssertEqual(CrossServerSearch.normalize(" \u{201C}Harbor\u{201D}? "), "Harbor")
        XCTAssertEqual(CrossServerSearch.normalize("夜の港。"), "夜の港")
        XCTAssertEqual(CrossServerSearch.normalize("Mr. Willow"), "Mr. Willow", "inner punctuation stays")
        XCTAssertNil(CrossServerSearch.normalize(" . "))
    }
}

final class PosterBadgesTests: XCTestCase {
    func testKavitaShowsPageProgress() {
        let b = PosterBadges(series: series("1", "A", unread: 150, pages: 200, read: 50), caption: .pages)
        XCTAssertEqual(b.corner, .none, "unread pages are not a badge")
        XCTAssertEqual(b.progress, 0.25)
        XCTAssertEqual(b.caption, "200 pages")
        XCTAssertEqual(PosterBadges(series: series("1", "A", pages: 1200, read: 1200)).corner, .finished)
        XCTAssertEqual(PosterBadges(series: series("1", "A", pages: 1200, read: 0), caption: .pages).caption, "1,200 pages")
        XCTAssertNil(PosterBadges(series: series("1", "A", pages: 10, read: 0)).progress)
    }

    func testChaptersIsTheDefaultCaption() {
        XCTAssertEqual(PosterCaption.default, .chapters)
        // Kavita lists pages only: no caption until the count arrives.
        let kavita = series("1", "A", unread: 150, pages: 1383, read: 50)
        XCTAssertNil(PosterBadges(series: kavita).caption)
        XCTAssertTrue(PosterCaption.chapters.needsChapterCount(kavita))
        let counted = kavita.withCount(SeriesCount(count: 42))
        XCTAssertEqual(PosterBadges(series: counted).caption, "42 chapters")
        XCTAssertEqual(PosterBadges(series: counted).progress, PosterBadges(series: kavita).progress, "badges unchanged")
        XCTAssertFalse(PosterCaption.chapters.needsChapterCount(counted))
        XCTAssertEqual(PosterBadges(series: kavita.withCount(SeriesCount(count: 1))).caption, "1 chapter")
        XCTAssertEqual(PosterBadges(series: kavita.withCount(SeriesCount(count: 12, unit: .volume))).caption, "12 volumes")
        XCTAssertEqual(PosterBadges(series: kavita.withCount(SeriesCount(count: 1, unit: .book))).caption, "1 book")
        XCTAssertEqual(series("1", "A", chapters: 3).withCount(SeriesCount(count: 9)).chapterCount, 3, "listing wins")
    }

    func testPageListingsGetAnUnreadChapterBadge() {
        // Kavita: unreadCount is pages, so the badge waits for the chapter
        // count fetch, whatever the caption shows.
        let kavita = series("1", "A", unread: 150, pages: 1383, read: 50)
        XCTAssertEqual(PosterBadges(series: kavita, caption: .progress).corner, .none)
        XCTAssertTrue(PosterCaption.progress.needsChapterCount(kavita))
        XCTAssertTrue(PosterCaption.off.needsChapterCount(kavita))
        let counted = kavita.withCount(SeriesCount(count: 42, unread: 30))
        XCTAssertEqual(counted.unreadChapters, 30)
        XCTAssertEqual(PosterBadges(series: counted, caption: .progress).corner, .unread(30))
        XCTAssertFalse(PosterCaption.progress.needsChapterCount(counted))
        // Unread series (0%) get the badge too.
        let fresh = series("1", "A", unread: 100, pages: 100, read: 0).withCount(SeriesCount(count: 5, unread: 5))
        XCTAssertEqual(PosterBadges(series: fresh, caption: .progress).corner, .unread(5))
        // Finished: a check, and no fetch needed.
        let done = series("1", "A", unread: 0, pages: 100, read: 100)
        XCTAssertFalse(PosterCaption.progress.needsChapterCount(done))
        XCTAssertEqual(PosterBadges(series: done.withCount(SeriesCount(count: 5, unread: 0))).corner, .finished)
        // Chapter listings keep their own unread count.
        XCTAssertNil(series("1", "A", unread: 3, chapters: 12).withCount(SeriesCount(count: 12, unread: 9)).unreadChapters)
        // Reading updates it, and a guest never sees the owner's.
        let read = SeriesProgressOverride(unreadCount: 4, chapterCount: 42, pageCount: 1383, pagesRead: 900).applied(to: counted)
        XCTAssertEqual(PosterBadges(series: read).corner, .unread(4))
        XCTAssertNil(GuestSession.withoutServerProgress(counted).unreadChapters)
    }

    func testPagesFallBackToChapters() {
        XCTAssertEqual(PosterBadges(series: series("1", "A", unread: 3, chapters: 12), caption: .pages).caption, "12 chapters")
        XCTAssertFalse(PosterCaption.pages.needsChapterCount(series("1", "A", pages: 10, read: 0)))
        XCTAssertTrue(PosterCaption.pages.needsChapterCount(series("1", "A", unread: 2)))
    }

    func testProgressAndOffCaptions() {
        let b = PosterBadges(series: series("1", "A", unread: 3, chapters: 12), caption: .progress)
        XCTAssertNil(b.caption)
        XCTAssertEqual(b.titleProgress, 0.75)
        XCTAssertEqual(b.corner, .unread(3), "corner badge stays")
        XCTAssertEqual(PosterBadges(series: series("1", "A", unread: 4, chapters: 4), caption: .progress).titleProgress, 0,
                       "unread series show an empty bar")
        XCTAssertEqual(PosterBadges(series: series("1", "A", pages: 10, read: 10), caption: .progress).titleProgress, 1)
        XCTAssertNil(PosterBadges(series: series("1", "A", unread: 4), caption: .progress).titleProgress, "nothing to measure")
        XCTAssertFalse(PosterCaption.progress.needsChapterCount(series("1", "A")))
        let off = PosterBadges(series: series("1", "A", unread: 3, chapters: 12), caption: .off)
        XCTAssertNil(off.caption)
        XCTAssertNil(off.titleProgress)
        XCTAssertEqual(off.corner, .unread(3))
        XCTAssertFalse(PosterCaption.off.needsChapterCount(series("1", "A")))
    }

    func testCountUnits() {
        let ref = SeriesRef(serverID: serverID, seriesID: "1")
        func chapter(_ format: ContentFormat?) -> Chapter {
            Chapter(id: UUID().uuidString, seriesRef: ref, title: "", number: 1, pageCount: 1, format: format)
        }
        XCTAssertEqual(SeriesCount(chapters: [chapter(nil), chapter(.images)]), SeriesCount(count: 2, unit: .chapter, unread: 2))
        XCTAssertEqual(SeriesCount(chapters: [chapter(.epub), chapter(.pdf)]), SeriesCount(count: 2, unit: .book, unread: 2))
        XCTAssertEqual(SeriesCount(chapters: [chapter(nil)], seriesFormat: .epub).unit, .book)
        XCTAssertEqual(SeriesCount(chapters: []).count, 0)
    }

    func testSuwayomiShowsUnreadChapters() {
        let b = PosterBadges(series: series("1", "A", unread: 3, chapters: 12))
        XCTAssertEqual(b.corner, .unread(3))
        XCTAssertEqual(b.progress, 0.75)
        XCTAssertEqual(b.caption, "12 chapters")
        XCTAssertEqual(b.accessibilityValue, "3 unread, 75 percent read, 12 chapters")
        XCTAssertEqual(PosterBadges(series: series("1", "A", unread: 0, chapters: 1)).corner, .finished)
        XCTAssertEqual(PosterBadges(series: series("1", "A", unread: 0, chapters: 1)).caption, "1 chapter")
    }

    func testFallsBackToUnreadCount() {
        XCTAssertEqual(PosterBadges(series: series("1", "A", unread: 4)), PosterBadges(corner: .unread(4)))
        XCTAssertEqual(PosterBadges(series: series("1", "A", unread: 0)), PosterBadges())
        XCTAssertEqual(PosterBadges(series: series("1", "A")), PosterBadges())
    }
}

final class HomeLayoutTests: XCTestCase {
    func testDefaultOrderAndHiding() {
        var layout = HomeLayout()
        XCTAssertEqual(layout.visibleRows, HomeLayout.defaultOrder)
        XCTAssertTrue(layout.isDefault)
        layout.setHidden(.newlyAdded, true)
        XCTAssertFalse(layout.visibleRows.contains(.newlyAdded))
        XCTAssertTrue(layout.rows.contains(.newlyAdded), "hidden rows keep their place")
        layout.setHidden(.newlyAdded, false)
        XCTAssertTrue(layout.isDefault)
    }

    func testMoving() {
        var layout = HomeLayout()
        XCTAssertFalse(layout.canMove(.continueReading, by: -1))
        XCTAssertTrue(layout.canMove(.continueReading, by: 1))
        layout.move(.caughtUp, by: -10)
        XCTAssertEqual(layout.rows.first, .caughtUp)
        layout.move(.favorites, by: 1)
        XCTAssertEqual(layout.rows, [.caughtUp, .continueReading, .recentlyUpdated, .favorites, .newlyAdded])
        layout.move(.favorites, by: 99)
        XCTAssertEqual(layout.rows.last, .favorites)
        XCTAssertFalse(layout.canMove(.favorites, by: 1))
    }

    func testDecodingKeepsKnownKindsAndRestoresMissingOnes() throws {
        // Saved by a version without Caught Up, plus a kind from the future.
        let json = #"{"order":["newlyAdded","futureRow","continueReading","favorites","recentlyUpdated"],"hidden":["favorites","futureRow"]}"#
        let layout = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.rows, [.newlyAdded, .caughtUp, .continueReading, .favorites, .recentlyUpdated],
                       "Caught Up goes back after New, which precedes it by default")
        XCTAssertEqual(layout.hidden, [.favorites])
        XCTAssertEqual(layout.visibleRows, [.newlyAdded, .caughtUp, .continueReading, .recentlyUpdated])
    }
}

final class BrowsePreferencesTests: XCTestCase {
    let profile = UUID()

    /// Settings > Theme was removed (2026-11-28). Preferences saved with a
    /// theme still decode, keep everything else, and drop the theme on save.
    func testStoredThemeFromOlderVersionIsIgnored() throws {
        let old = Data(#"{"theme":"blackStock","gridDensity":"compact","showsProgressPercent":false}"#.utf8)
        let prefs = try JSONDecoder().decode(BrowsePreferences.self, from: old)
        XCTAssertEqual(prefs.gridDensity, .compact)
        XCTAssertFalse(prefs.showsProgressPercent)
        let encoded = String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self)
        XCTAssertFalse(encoded.contains("theme"), encoded)
        XCTAssertEqual(try JSONDecoder().decode(BrowsePreferences.self, from: Data(#"{"theme":"celadon"}"#.utf8)),
                       BrowsePreferences())
    }

    func testDefaultsEncodeToNothingAndOldStateDecodes() throws {
        let data = try JSONEncoder().encode(BrowsePreferences())
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")
        var prefs = BrowsePreferences()
        prefs.posterCaption = .progress
        let encoded = try JSONEncoder().encode(prefs)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"posterCaption":"progress"}"#)
        XCTAssertEqual(try JSONDecoder().decode(BrowsePreferences.self, from: encoded).posterCaption, .progress)
        XCTAssertEqual(try JSONDecoder().decode(BrowsePreferences.self, from: Data(#"{"posterCaption":"sparkles"}"#.utf8)).posterCaption,
                       .chapters, "unknown values fall back")
        let old = #"{"serverSettings":{},"favorites":[],"progress":{},"defaultReaderSettings":{"mode":"paged","direction":"rightToLeft","layout":"double","firstPageAlone":true,"shiftPairing":false,"background":"black","webtoonWidth":0.6,"webtoonScrollStep":0.75},"readerOverrides":{}}"#
        let decoded = try JSONDecoder().decode(ProfileData.self, from: Data(old.utf8))
        XCTAssertNil(decoded.browse)
        let summary = #"{"ref":{"serverID":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","seriesID":"1"},"title":"T","unreadCount":2}"#
        let s = try JSONDecoder().decode(SeriesSummary.self, from: Data(summary.utf8))
        XCTAssertNil(s.pageCount)
        XCTAssertNil(s.chapterCount)
    }

    func testRoundTripThroughStateStore() {
        var state = AppState.initial()
        let p = state.activeProfile!.id
        let key = LibraryKey(serverID: serverID, categoryID: "4")
        state.updateBrowse(profile: p) {
            $0.gridDensity = .compact
            $0.home.setHidden(.newlyAdded, true)
            $0.setOptions(LibraryOptions(sort: .recentlyAdded, readingStyle: .rightToLeft), for: key)
        }
        let store = StateStore(backing: InMemoryKeyValueStore())
        store.save(state)
        let loaded = store.load().browse(profile: p)
        XCTAssertEqual(loaded.gridDensity, .compact)
        XCTAssertTrue(loaded.home.isHidden(.newlyAdded))
        XCTAssertEqual(loaded.options(for: key).sort, .recentlyAdded)

        // Back to defaults stores nothing.
        state.updateBrowse(profile: p) { $0 = BrowsePreferences() }
        XCTAssertNil(state.profileData[p.uuidString]?.browse)
    }

    func testLibraryReadingStyleAppliesUnlessSeriesHasOwnSettings() {
        var state = AppState.initial()
        let p = state.activeProfile!.id
        state.setDefaultReaderSettings(ReaderSettings(mode: .paged, direction: .rightToLeft), profile: p)
        state.updateBrowse(profile: p) {
            $0.setOptions(LibraryOptions(readingStyle: .leftToRight), for: LibraryKey(serverID: serverID, categoryID: "comics"))
            $0.setOptions(LibraryOptions(readingStyle: .vertical), for: LibraryKey(serverID: serverID, categoryID: "webtoon"))
        }
        let comic = series("1", "Orbit", library: "comics")
        let strip = series("2", "Summit", categories: ["webtoon", "comics"])
        let other = series("3", "Meadow", library: "manga")
        XCTAssertEqual(state.readerSettings(for: comic, profile: p).direction, .leftToRight)
        XCTAssertEqual(state.readerSettings(for: strip, profile: p).mode, .webtoon, "first category with a style wins")
        XCTAssertEqual(state.readerSettings(for: other, profile: p), ReaderSettings(mode: .paged, direction: .rightToLeft))

        let own = ReaderSettings(mode: .paged, direction: .rightToLeft, layout: .single)
        state.setReaderSettings(own, for: comic.ref, profile: p)
        XCTAssertEqual(state.readerSettings(for: comic, profile: p), own)
        XCTAssertEqual(state.defaultReaderSettings(for: comic, profile: p).direction, .leftToRight,
                       "Reset to Default goes back to the library's style")
    }

    func testDismissedContinueReadingReturnsWhenReadAgain() {
        var state = AppState.initial()
        let p = state.activeProfile!.id
        let a = series("1", "A"), b = series("2", "B")
        state.recordProgress(a.ref, chapterID: "c1", page: 2, completed: false, profile: p, now: Date(timeIntervalSince1970: 100))
        state.updateBrowse(profile: p) { $0.dismissFromContinueReading(a.ref, at: Date(timeIntervalSince1970: 200)) }
        XCTAssertEqual(state.filterContinueReading([a, b], profile: p).map(\.title), ["B"])
        state.recordProgress(a.ref, chapterID: "c1", page: 3, completed: false, profile: p, now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(state.filterContinueReading([a, b], profile: p).map(\.title), ["A", "B"])
    }

    func testCaughtUpFollowsSeriesDetail() {
        var prefs = BrowsePreferences()
        let s = series("1", "Willow", unread: 1)
        func detail(read: [Bool]) -> SeriesDetail {
            SeriesDetail(summary: s, synopsis: nil, authors: [], genres: [], status: nil,
                         chapters: read.enumerated().map { i, r in
                             Chapter(id: "\(i)", seriesRef: s.ref, title: "Chapter \(i + 1)", number: Double(i + 1),
                                     pageCount: 20, isRead: r)
                         })
        }
        prefs.noteCaughtUp(detail(read: [true, false]), now: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(prefs.caughtUp.isEmpty)
        prefs.noteCaughtUp(detail(read: [true, true]), now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(prefs.caughtUp.map(\.series.title), ["Willow"])
        XCTAssertEqual(prefs.caughtUp.first?.series.unreadCount, 0)
        prefs.noteCaughtUp(detail(read: [true, true]), now: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(prefs.caughtUp.first?.caughtUpAt, Date(timeIntervalSince1970: 2), "seeing it again keeps the date")

        XCTAssertFalse(prefs.pruneCaughtUp(seenIn: [series("1", "Willow", unread: 0)]))
        XCTAssertTrue(prefs.pruneCaughtUp(seenIn: [series("1", "Willow", unread: 2)]), "a new chapter ends Caught Up")
        XCTAssertTrue(prefs.caughtUp.isEmpty)

        for n in 0..<(BrowsePreferences.caughtUpLimit + 5) {
            let other = series("x\(n)", "S\(n)")
            prefs.noteCaughtUp(SeriesDetail(summary: other, synopsis: nil, authors: [], genres: [], status: nil,
                                            chapters: [Chapter(id: "c", seriesRef: other.ref, title: "1", number: 1, pageCount: 1, isRead: true)]),
                               now: Date(timeIntervalSince1970: Double(10 + n)))
        }
        XCTAssertEqual(prefs.caughtUp.count, BrowsePreferences.caughtUpLimit)
        XCTAssertEqual(prefs.caughtUp.first?.series.title, "S\(BrowsePreferences.caughtUpLimit + 4)", "newest first")
    }

    func testRemovingServerClearsItsBrowseData() {
        var state = AppState.initial()
        let p = state.activeProfile!.id
        let server = ServerConfig(id: serverID, kind: .kavita, name: "K", baseURL: URL(string: "http://k")!)
        state.addServer(server)
        state.updateBrowse(profile: p) {
            $0.gridDensity = .large
            $0.setOptions(LibraryOptions(sort: .recentlyRead), for: LibraryKey(serverID: serverID, categoryID: "1"))
            $0.dismissFromContinueReading(series("1", "A").ref, at: Date())
        }
        XCTAssertEqual(state.visibleCaughtUp(profile: p).count, 0)
        state.removeServer(serverID)
        let prefs = state.browse(profile: p)
        XCTAssertTrue(prefs.libraries.isEmpty)
        XCTAssertTrue(prefs.dismissedContinueReading.isEmpty)
        XCTAssertEqual(prefs.gridDensity, .large, "profile-wide settings stay")
    }
}

final class LibrarySortClientTests: XCTestCase {
    func testKavitaSendsSortOptions() async throws {
        let mock = MockTransport()
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"u","token":"jwt"}"#)
        mock.on("POST", "api/Series/v2", body: #"[{"id":5,"name":"Harbor Lights","pages":40,"pagesRead":10,"libraryId":1}]"#)
        let client = KavitaClient(config: ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://k.local")!),
                                  apiKey: "KEY", transport: mock)
        let page = try await client.series(in: MangaCategory(id: "1", name: "L"), page: 1, pageSize: 10, sort: .recentlyRead)
        XCTAssertEqual(page.items.first?.pageCount, 40)
        XCTAssertEqual(page.items.first?.pagesRead, 10)
        let sort = try XCTUnwrap(jsonBody(mock.lastRequest(containing: "api/Series/v2"))["sortOptions"] as? [String: Any])
        XCTAssertEqual(sort["sortField"] as? Int, 7)
        XCTAssertEqual(sort["isAscending"] as? Bool, false)

        _ = try await client.series(in: MangaCategory(id: "1", name: "L"), page: 1, pageSize: 10)
        let plain = try XCTUnwrap(jsonBody(mock.lastRequest(containing: "api/Series/v2"))["sortOptions"] as? [String: Any])
        XCTAssertEqual(plain["sortField"] as? Int, 1)
        XCTAssertEqual(plain["isAscending"] as? Bool, true)
        XCTAssertEqual(KavitaClient.sortOptions(.recentlyUpdated).sortField, 4)
        XCTAssertEqual(KavitaClient.sortOptions(.recentlyAdded).sortField, 2)
        XCTAssertEqual(KavitaClient.sortOptions(.titleDescending).isAscending, false)
    }

    func testSuwayomiSortsByDatesAndCachesLaterPages() async throws {
        let mock = MockTransport()
        mock.onGraphQL("category(id", body: """
        {"data":{"category":{"mangas":{"nodes":[
          {"id":1,"title":"Amber Road","unreadCount":2,"inLibrary":true,"inLibraryAt":"1700000100","chapters":{"totalCount":8},"lastReadChapter":{"lastReadAt":"1700000500"}},
          {"id":2,"title":"Birch Hollow","unreadCount":0,"inLibrary":true,"inLibraryAt":"1700000300","chapters":{"totalCount":4},"lastReadChapter":null},
          {"id":3,"title":"Cedar Gate","unreadCount":5,"inLibrary":true,"inLibraryAt":"1700000200","chapters":{"totalCount":5},"lastReadChapter":{"lastReadAt":"0"}}
        ]}}}}
        """)
        let client = SuwayomiClient(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://s.local")!),
                                    username: nil, password: nil, transport: mock)
        let cat = MangaCategory(id: "1", name: "C")
        let added = try await client.series(in: cat, page: 1, pageSize: 2, sort: .recentlyAdded)
        XCTAssertEqual(added.items.map(\.title), ["Birch Hollow", "Cedar Gate"])
        XCTAssertEqual(added.items.first?.chapterCount, 4)
        XCTAssertTrue(added.hasMore)
        let rest = try await client.series(in: cat, page: 2, pageSize: 2, sort: .recentlyAdded)
        XCTAssertEqual(rest.items.map(\.title), ["Amber Road"])
        XCTAssertEqual(mock.requests.count, 1, "page 2 reuses page 1's download")

        let read = try await client.series(in: cat, page: 1, pageSize: 3, sort: .recentlyRead)
        XCTAssertEqual(read.items.map(\.title), ["Amber Road", "Birch Hollow", "Cedar Gate"], "never read goes last, by title")
        XCTAssertEqual(mock.requests.count, 2, "page 1 always refreshes")
        let body = String(decoding: mock.requests.last?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("inLibraryAt"), body)
    }

    func testSuwayomiFallsBackWhenServerRejectsExtraFields() async throws {
        let mock = MockTransport()
        mock.onGraphQL("inLibraryAt", body: #"{"errors":[{"message":"Validation error: Field 'inLibraryAt' undefined"}]}"#)
        mock.onGraphQL("category(id", body: #"{"data":{"category":{"mangas":{"nodes":[{"id":1,"title":"Quiet Pond","unreadCount":1,"inLibrary":true}]}}}}"#)
        let client = SuwayomiClient(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://s.local")!),
                                    username: nil, password: nil, transport: mock)
        let page = try await client.series(in: MangaCategory(id: "1", name: "C"), page: 1, pageSize: 10, sort: .recentlyUpdated)
        XCTAssertEqual(page.items.map(\.title), ["Quiet Pond"])
        XCTAssertNil(page.items.first?.chapterCount)
        XCTAssertEqual(mock.requests.count, 2)
    }

    func testDemoServerSortsByTitle() async throws {
        let server = SampleLibraryServer(config: ServerConfig(kind: .kavita, name: "D", baseURL: URL(string: "https://demo.invalid")!),
                                         seriesCount: 20, latency: .zero)
        let all = MangaCategory(id: "all", name: "All")
        let asc = try await server.series(in: all, page: 1, pageSize: 20, sort: .titleAscending).items.map(\.title)
        XCTAssertEqual(Array(asc.prefix(3)), ["Ember Chronicles 1", "Ember Chronicles 9", "Ember Chronicles 17"])
        XCTAssertEqual(asc.last, "Zephyr Chronicles 16")
        let desc = try await server.series(in: all, page: 1, pageSize: 20, sort: .titleDescending).items.map(\.title)
        XCTAssertEqual(desc, asc.reversed())
        let added = try await server.series(in: all, page: 1, pageSize: 3, sort: .recentlyAdded).items.map(\.ref.seriesID)
        XCTAssertEqual(added, ["20", "19", "18"])
        XCTAssertEqual(AlphabetIndex.jump(to: "M", in: asc, hasMore: false), .index(asc.firstIndex(of: "Meadow Chronicles 4")!))
    }
}

final class ChapterRowDetailTests: XCTestCase {
    func testUnreadChaptersShowPageCount() {
        let ref = SeriesRef(serverID: serverID, seriesID: "1")
        XCTAssertEqual(Chapter(id: "1", seriesRef: ref, title: "Volume 1", number: 1, pageCount: 184).rowDetail, "184 pages")
        XCTAssertEqual(Chapter(id: "1", seriesRef: ref, title: "Volume 1", number: 1, pageCount: 1).rowDetail, "1 page")
        XCTAssertEqual(Chapter(id: "1", seriesRef: ref, title: "C", number: 1, pageCount: 0).rowDetail, "", "Suwayomi before pages load")
        XCTAssertEqual(Chapter(id: "1", seriesRef: ref, title: "C", number: 1, pageCount: 20, lastPageRead: 4).rowDetail, "Page 5 of 20")
        XCTAssertEqual(Chapter(id: "1", seriesRef: ref, title: "C", number: 1, pageCount: 20, isRead: true).rowDetail, "Read")
    }
}

final class DemoFinishedSeriesTests: XCTestCase {
    func testMarkAllReadFinishesTheSeries() async throws {
        let server = SampleLibraryServer(config: ServerConfig(kind: .kavita, name: "D", baseURL: URL(string: "https://demo.invalid")!),
                                         latency: .zero)
        server.markAllRead(seriesID: "1")
        let detail = try await server.seriesDetail("1")
        XCTAssertTrue(detail.chapters.allSatisfy(\.isRead))
        var prefs = BrowsePreferences()
        prefs.noteCaughtUp(detail, now: Date())
        XCTAssertEqual(prefs.caughtUp.map(\.series.ref.seriesID), ["1"])
        let page = try await server.series(in: MangaCategory(id: "all", name: "All"), page: 1, pageSize: 1)
        XCTAssertEqual(PosterBadges(series: page.items[0]).corner, .finished)
    }
}
