import XCTest
@testable import MangaCore

final class GuestSessionTests: XCTestCase {
    let kavita = ServerConfig(kind: .kavita, name: "Kavita", baseURL: URL(string: "http://kavita.local")!)
    let suwayomi = ServerConfig(kind: .suwayomi, name: "Suwayomi", baseURL: URL(string: "http://suwayomi.local")!)

    private func ownerState() -> (AppState, UUID) {
        var s = AppState.initial()
        let owner = s.profiles[0].id
        s.addProfile(name: "Kid")
        s.addServer(kavita)
        s.addServer(suwayomi)
        s.setSelectedCategories(["2"], profile: owner, server: kavita.id)
        var reader = ReaderSettings.default
        reader.mode = .webtoon
        s.setDefaultReaderSettings(reader, profile: owner)
        let series = SeriesSummary(ref: SeriesRef(serverID: kavita.id, seriesID: "7"), title: "Ember", coverURL: nil)
        s.setFavorite(series, true, profile: owner)
        s.recordProgress(series.ref, chapterID: "70", page: 5, completed: false, profile: owner, series: series)
        s.setReaderSettings(.default, for: series.ref, profile: owner)
        s.noteRecentSeries(series, profile: owner)
        s.freeLibraryRemoved = true
        return (s, owner)
    }

    func testGuestStateHasOnlyTheGuestAndTheOwnersServers() {
        let (owner, host) = ownerState()
        let guest = GuestSession(hostProfileID: host).makeState(from: owner)
        XCTAssertEqual(guest.profiles, [GuestSession.profile])
        XCTAssertEqual(guest.activeProfile?.id, GuestSession.profileID)
        XCTAssertEqual(guest.servers, owner.servers)
        XCTAssertEqual(Array(guest.profileData.keys), [GuestSession.profileID.uuidString])
        XCTAssertNil(guest.rememberedProfileID)
        XCTAssertEqual(guest.freeLibraryRemoved, true)
    }

    func testGuestStartsWithNoneOfTheOwnersReading() {
        let (owner, host) = ownerState()
        let guest = GuestSession(hostProfileID: host).makeState(from: owner)
        let me = GuestSession.profileID
        let ref = SeriesRef(serverID: kavita.id, seriesID: "7")
        XCTAssertTrue(guest.favorites(profile: me).isEmpty)
        XCTAssertNil(guest.progress(ref, profile: me))
        XCTAssertTrue(guest.bookmarks(profile: me).isEmpty)
        let data = guest.profileData[me.uuidString]!
        XCTAssertTrue(data.readerOverrides.isEmpty)
        XCTAssertNil(data.recentSeries)
        XCTAssertNil(data.browse)
    }

    func testGuestNeverSyncsButKeepsTheHostsLibrariesAndReaderDefaults() {
        let (owner, host) = ownerState()
        let guest = GuestSession(hostProfileID: host).makeState(from: owner)
        let me = GuestSession.profileID
        for server in owner.servers {
            XCTAssertFalse(guest.serverSettings(profile: me, server: server.id).syncProgressToServer, server.name)
        }
        XCTAssertEqual(guest.selectedCategories(profile: me, server: kavita.id), ["2"])
        XCTAssertNil(guest.selectedCategories(profile: me, server: suwayomi.id))
        XCTAssertEqual(guest.profileData[me.uuidString]?.defaultReaderSettings.mode, .webtoon)
    }

    func testGuestReadingStaysOutOfTheOwnersState() {
        let (owner, host) = ownerState()
        var guest = GuestSession(hostProfileID: host).makeState(from: owner)
        let before = owner
        let me = GuestSession.profileID
        let other = SeriesSummary(ref: SeriesRef(serverID: kavita.id, seriesID: "9"), title: "Harbor", coverURL: nil)
        guest.setFavorite(other, true, profile: me)
        guest.recordProgress(other.ref, chapterID: "90", page: 3, completed: true, profile: me, series: other)
        XCTAssertTrue(guest.isFavorite(other.ref, profile: me))
        XCTAssertEqual(owner, before)
        XCTAssertFalse(owner.isFavorite(other.ref, profile: host))
        XCTAssertNil(owner.progress(other.ref, profile: host))
    }

    func testGuestSeesEveryChapterUnreadThenTheirOwnProgress() {
        let ref = SeriesRef(serverID: kavita.id, seriesID: "7")
        let detail = SeriesDetail(
            summary: SeriesSummary(ref: ref, title: "Ember", coverURL: nil, unreadCount: 1, pagesRead: 40),
            synopsis: nil, authors: [], genres: [], status: nil,
            chapters: [
                Chapter(id: "1", seriesRef: ref, title: "1", number: 1, pageCount: 20, lastPageRead: 19, isRead: true,
                        lastReadAt: Date(timeIntervalSince1970: 100)),
                Chapter(id: "2", seriesRef: ref, title: "2", number: 2, pageCount: 20, lastPageRead: 7,
                        lastReadAt: Date(timeIntervalSince1970: 200)),
            ])
        let stripped = GuestSession.withoutServerProgress(detail)
        XCTAssertNil(stripped.summary.unreadCount)
        XCTAssertNil(stripped.summary.pagesRead)
        XCTAssertEqual(stripped.chapters.map(\.isRead), [false, false])
        XCTAssertEqual(stripped.chapters.map(\.lastPageRead), [0, 0])
        XCTAssertEqual(stripped.chapters.compactMap(\.lastReadAt), [])
        XCTAssertEqual(stripped.posterUnreadCount, 2)
        XCTAssertEqual(stripped.continueChapter?.id, "1")

        var guest = GuestSession(hostProfileID: UUID()).makeState(from: AppState.initial())
        guest.recordProgress(ref, chapterID: "1", page: 19, completed: true, profile: GuestSession.profileID)
        guest.recordProgress(ref, chapterID: "2", page: 4, completed: false, profile: GuestSession.profileID)
        let mine = guest.applyingLocalProgress(to: stripped, profile: GuestSession.profileID)
        XCTAssertEqual(mine.chapters.map(\.isRead), [true, false])
        XCTAssertEqual(mine.chapters[1].lastPageRead, 4)
        XCTAssertEqual(mine.continueChapter?.id, "2")
    }

    func testGuestIDIsNeverARealProfile() {
        var s = AppState.initial()
        for _ in 0..<20 { s.addProfile(name: "P") }
        XCTAssertFalse(s.profiles.contains { $0.id == GuestSession.profileID })
    }
}
