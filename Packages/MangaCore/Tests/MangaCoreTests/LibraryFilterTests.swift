import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Library filters (status, read progress, genres) and Library Defaults.
/// Titles and genres are made up for the tests.
final class LibraryFilterTests: XCTestCase {
    // MARK: Matching

    func testReadProgressMatching() {
        XCTAssertTrue(ReadProgressFilter.any.matches(unread: nil, total: nil))
        XCTAssertTrue(ReadProgressFilter.unread.matches(unread: 5, total: 5))
        XCTAssertFalse(ReadProgressFilter.unread.matches(unread: 4, total: 5))
        XCTAssertTrue(ReadProgressFilter.inProgress.matches(unread: 4, total: 5))
        XCTAssertFalse(ReadProgressFilter.inProgress.matches(unread: 0, total: 5))
        XCTAssertFalse(ReadProgressFilter.inProgress.matches(unread: 5, total: 5))
        XCTAssertTrue(ReadProgressFilter.unfinished.matches(unread: 5, total: 5))
        XCTAssertTrue(ReadProgressFilter.unfinished.matches(unread: 1, total: 5))
        XCTAssertFalse(ReadProgressFilter.unfinished.matches(unread: 0, total: 5))
        XCTAssertTrue(ReadProgressFilter.read.matches(unread: 0, total: 5))
        XCTAssertFalse(ReadProgressFilter.read.matches(unread: 0, total: 0), "an empty series isn't finished")
        XCTAssertFalse(ReadProgressFilter.read.matches(unread: nil, total: 5), "unknown counts fail a read filter")
    }

    func testFilterCombinesPartsAndAlternatives() {
        let filter = LibraryFilter(statuses: [.ongoing, .hiatus], readProgress: .unfinished, genres: ["Comédie"])
        XCTAssertTrue(filter.matches(status: .hiatus, unread: 2, total: 9, genres: ["comedie", "Drama"]),
                      "genres match without case or accents")
        XCTAssertFalse(filter.matches(status: .completed, unread: 2, total: 9, genres: ["Comédie"]))
        XCTAssertFalse(filter.matches(status: nil, unread: 2, total: 9, genres: ["Comédie"]), "no status fails a status filter")
        XCTAssertFalse(filter.matches(status: .ongoing, unread: 0, total: 9, genres: ["Comédie"]))
        XCTAssertFalse(filter.matches(status: .ongoing, unread: 2, total: 9, genres: ["Drama"]))
        XCTAssertFalse(filter.matches(status: .ongoing, unread: 2, total: 9, genres: nil))
        XCTAssertTrue(LibraryFilter.empty.matches(status: nil, unread: nil, total: nil, genres: nil))
    }

    func testLimitedToSupportAndCounts() {
        let filter = LibraryFilter(statuses: [.completed], readProgress: .read, genres: ["Mystery"])
        XCTAssertEqual(filter.activeCount, 3)
        let genresOnly = filter.limited(to: .genres)
        XCTAssertEqual(genresOnly, LibraryFilter(genres: ["Mystery"]))
        XCTAssertTrue(filter.limited(to: []).isEmpty)
        XCTAssertEqual(filter.forDefault, LibraryFilter(statuses: [.completed], readProgress: .read))
    }

    func testSummaryAndKey() {
        XCTAssertEqual(LibraryFilter.empty.summary, "Everything")
        let filter = LibraryFilter(statuses: [.hiatus, .ongoing], readProgress: .unfinished)
        XCTAssertEqual(filter.summary, "Ongoing or On Hiatus, Not Finished")
        XCTAssertEqual(filter.key, LibraryFilter(statuses: [.ongoing, .hiatus], readProgress: .unfinished).key)
        XCTAssertNotEqual(filter.key, LibraryFilter.empty.key)
    }

    func testGenreListDedupesAndSorts() {
        XCTAssertEqual(LibraryFilter.genreList(["Mystery", " comedy", "Comedy", "", "Adventure 10", "Adventure 2"]),
                       ["Adventure 2", "Adventure 10", "comedy", "Mystery"])
    }

    func testStatusMappings() {
        XCTAssertEqual(PublicationStatus(suwayomi: "ONGOING"), .ongoing)
        XCTAssertEqual(PublicationStatus(suwayomi: "PUBLISHING_FINISHED"), .completed)
        XCTAssertEqual(PublicationStatus(suwayomi: "ON_HIATUS"), .hiatus)
        XCTAssertEqual(PublicationStatus(suwayomi: "CANCELLED"), .cancelled)
        XCTAssertNil(PublicationStatus(suwayomi: "LICENSED"))
        XCTAssertNil(PublicationStatus(suwayomi: nil))
        XCTAssertEqual(PublicationStatus.completed.kavitaValues, [2, 4])
        XCTAssertEqual(PublicationStatus.cancelled.komgaValue, "ABANDONED")
    }

    // MARK: Persistence and defaults

    func testFilterCodingIsCompactAndTolerant() throws {
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(LibraryFilter.empty), as: UTF8.self), "{}")
        let json = #"{"statuses":["ongoing","fromTheFuture"],"readProgress":"somethingNew","genres":["Mystery"]}"#
        let decoded = try JSONDecoder().decode(LibraryFilter.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, LibraryFilter(statuses: [.ongoing], genres: ["Mystery"]))
        let filter = LibraryFilter(statuses: [.completed, .hiatus], readProgress: .inProgress, genres: ["B", "A"])
        XCTAssertEqual(try JSONDecoder().decode(LibraryFilter.self, from: JSONEncoder().encode(filter)), filter)
    }

    func testLibraryOptionsResolveFromDefaults() {
        let defaults = LibraryDefaults(sort: .recentlyUpdated, gridOrder: .rightToLeft,
                                       filter: LibraryFilter(statuses: [.ongoing], genres: ["Dropped"]))
        XCTAssertTrue(defaults.filter.genres.isEmpty, "defaults never keep genres")
        let unset = LibraryOptions().resolved(with: defaults)
        XCTAssertEqual(unset.sort, .recentlyUpdated)
        XCTAssertEqual(unset.gridOrder, .rightToLeft)
        XCTAssertEqual(unset.filter, LibraryFilter(statuses: [.ongoing]))
        XCTAssertTrue(unset.gridIsRightToLeft)

        let own = LibraryOptions(sort: .titleDescending, gridOrder: .leftToRight, filter: .empty).resolved(with: defaults)
        XCTAssertEqual(own.sort, .titleDescending)
        XCTAssertEqual(own.gridOrder, .leftToRight)
        XCTAssertEqual(own.filter, .empty, "a library's own empty filter overrides the default")
        XCTAssertFalse(LibraryOptions(filter: .empty).isEmpty)
    }

    func testBrowsePreferencesPersistDefaultsAndFilters() throws {
        let profile = UUID()
        let server = UUID()
        let key = LibraryKey(serverID: server, categoryID: "3")
        var state = AppState(profiles: [Profile(id: profile, name: "P")], activeProfileID: profile,
                             profileData: [profile.uuidString: ProfileData()])
        state.updateBrowse(profile: profile) {
            $0.libraryDefaults = LibraryDefaults(sort: .recentlyAdded, filter: LibraryFilter(readProgress: .unfinished))
            $0.setOptions(LibraryOptions(filter: LibraryFilter(statuses: [.completed], genres: ["Mystery"])), for: key)
        }
        let loaded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        let prefs = loaded.browse(profile: profile)
        XCTAssertEqual(prefs.libraryDefaults.sort, .recentlyAdded)
        XCTAssertEqual(prefs.resolvedOptions(for: key).filter, LibraryFilter(statuses: [.completed], genres: ["Mystery"]))
        XCTAssertEqual(prefs.resolvedOptions(for: key).sort, .recentlyAdded)
        let other = LibraryKey(serverID: server, categoryID: "4")
        XCTAssertEqual(prefs.resolvedOptions(for: other).filter, LibraryFilter(readProgress: .unfinished))

        state.updateBrowse(profile: profile) {
            $0.libraryDefaults = .default
            $0.setOptions(LibraryOptions(), for: key)
        }
        XCTAssertNil(state.profileData[profile.uuidString]?.browse, "all-default prefs aren't stored")
    }

    func testOlderBrowsePreferencesDecodeWithoutDefaults() throws {
        let json = #"{"libraries":{"x|1":{"sort":"recentlyRead"}}}"#
        let prefs = try JSONDecoder().decode(BrowsePreferences.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.libraryDefaults, .default)
        XCTAssertNil(prefs.libraries["x|1"]?.filter)
    }

    func testDefaultsSyncWithBrowsePreferences() throws {
        let profile = UUID()
        var state = AppState(profiles: [Profile(id: profile, name: "P")], activeProfileID: profile,
                             profileData: [profile.uuidString: ProfileData()])
        state.updateBrowse(profile: profile) {
            $0.libraryDefaults = LibraryDefaults(gridOrder: .leftToRight, filter: LibraryFilter(statuses: [.hiatus]))
        }
        let records = SyncMapper.payloads(from: state).map { key, item in
            SyncRecord(key: key, kind: item.kind, payload: item.payload, modifiedAt: Date(), deviceID: "t")
        }
        var restored = AppState()
        SyncMapper.apply(SyncPatch(records: records), to: &restored)
        XCTAssertEqual(restored.browse(profile: profile).libraryDefaults,
                       LibraryDefaults(gridOrder: .leftToRight, filter: LibraryFilter(statuses: [.hiatus])))
    }

    // MARK: Clients

    private let category = MangaCategory(id: "1", name: "L")

    private func kavita(_ mock: MockTransport) -> KavitaClient {
        mock.on("POST", "api/Plugin/authenticate", body: #"{"username":"u","token":"jwt"}"#)
        return KavitaClient(config: ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://k.local")!),
                            apiKey: "KEY", transport: mock)
    }

    func testKavitaSendsFilterStatements() async throws {
        let mock = MockTransport()
        mock.on("GET", "api/Metadata/genres", body: #"[{"id":4,"title":"Mystery"},{"id":9,"title":"Comedy"},{"id":2,"title":"Drama"}]"#)
        mock.on("POST", "api/Series/v2", body: #"[{"id":5,"name":"Harbor Lights","libraryId":1}]"#)
        let client = kavita(mock)
        XCTAssertEqual(client.libraryFilterSupport, .all)
        let filter = LibraryFilter(statuses: [.completed, .ongoing], readProgress: .inProgress, genres: ["comedy", "mystery"])
        let page = try await client.series(in: category, page: 1, pageSize: 10, sort: .titleAscending, filter: filter)
        XCTAssertEqual(page.items.map(\.title), ["Harbor Lights"])

        let body = jsonBody(mock.lastRequest(containing: "api/Series/v2"))
        let statements = try XCTUnwrap(body["statements"] as? [[String: Any]])
        let triples = statements.map { "\($0["field"] as? Int ?? -1):\($0["comparison"] as? Int ?? -1):\($0["value"] as? String ?? "")" }
        XCTAssertEqual(triples, ["19:0:1", "2:5:0,2,4", "20:1:0", "20:3:100", "18:5:4,9"])
        XCTAssertEqual(body["combination"] as? Int, 1)
        XCTAssertTrue(mock.lastRequest(containing: "api/Metadata/genres")?.url?.absoluteString.contains("libraryIds=1") ?? false)
    }

    func testKavitaUnknownGenreMatchesNothingWithoutListing() async throws {
        let mock = MockTransport()
        mock.on("GET", "api/Metadata/genres", body: #"[{"id":4,"title":"Mystery"}]"#)
        mock.on("POST", "api/Series/v2", body: #"[{"id":5,"name":"Harbor Lights","libraryId":1}]"#)
        let client = kavita(mock)
        let page = try await client.series(in: category, page: 1, pageSize: 10, sort: .titleAscending,
                                           filter: LibraryFilter(genres: ["Gone"]))
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(mock.lastRequest(containing: "api/Series/v2"))
    }

    func testKavitaReadProgressStatements() {
        func values(_ read: ReadProgressFilter) -> [String] {
            KavitaClient.statements(for: LibraryFilter(readProgress: read), genreIDs: []).map { "\($0.field):\($0.comparison):\($0.value)" }
        }
        XCTAssertEqual(values(.any), [])
        XCTAssertEqual(values(.unread), ["20:0:0"])
        XCTAssertEqual(values(.unfinished), ["20:3:100"])
        XCTAssertEqual(values(.read), ["20:0:100"])
    }

    func testKavitaGenreList() async throws {
        let mock = MockTransport()
        mock.on("GET", "api/Metadata/genres", body: #"[{"id":4,"title":"Mystery"},{"id":9,"title":"Comedy"}]"#)
        let genres = try await kavita(mock).filterGenres(in: category)
        XCTAssertEqual(genres, ["Comedy", "Mystery"])
    }

    private func suwayomi(_ mock: MockTransport) -> SuwayomiClient {
        mock.onGraphQL("category(id", body: """
        {"data":{"category":{"mangas":{"nodes":[
          {"id":1,"title":"Amber Road","unreadCount":8,"inLibrary":true,"chapters":{"totalCount":8},"status":"ONGOING","genre":["Mystery","Drama"]},
          {"id":2,"title":"Birch Hollow","unreadCount":0,"inLibrary":true,"chapters":{"totalCount":4},"status":"COMPLETED","genre":["Comedy"]},
          {"id":3,"title":"Cedar Lane","unreadCount":2,"inLibrary":true,"chapters":{"totalCount":6},"status":"ON_HIATUS","genre":["mystery"]},
          {"id":4,"title":"Dune Sea","unreadCount":3,"inLibrary":true,"chapters":{"totalCount":3},"status":"LICENSED","genre":[]}
        ]}}}}
        """)
        return SuwayomiClient(config: ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://s.local")!),
                              username: nil, password: nil, transport: mock)
    }

    func testSuwayomiFiltersOnTheClient() async throws {
        let client = suwayomi(MockTransport())
        func titles(_ filter: LibraryFilter) async throws -> [String] {
            try await client.series(in: category, page: 1, pageSize: 10, sort: .titleAscending, filter: filter).items.map(\.title)
        }
        let ongoing = try await titles(LibraryFilter(statuses: [.ongoing, .hiatus]))
        XCTAssertEqual(ongoing, ["Amber Road", "Cedar Lane"])
        let finished = try await titles(LibraryFilter(readProgress: .read))
        XCTAssertEqual(finished, ["Birch Hollow"])
        let started = try await titles(LibraryFilter(readProgress: .inProgress))
        XCTAssertEqual(started, ["Cedar Lane"])
        let notStarted = try await titles(LibraryFilter(readProgress: .unread))
        XCTAssertEqual(notStarted, ["Amber Road", "Dune Sea"])
        let mystery = try await titles(LibraryFilter(genres: ["MYSTERY"]))
        XCTAssertEqual(mystery, ["Amber Road", "Cedar Lane"])
        let everything = try await titles(.empty)
        XCTAssertEqual(everything.count, 4)
    }

    func testSuwayomiFilteredPagingAndGenres() async throws {
        let mock = MockTransport()
        let client = suwayomi(mock)
        let filter = LibraryFilter(readProgress: .unfinished)
        let first = try await client.series(in: category, page: 1, pageSize: 2, sort: .titleAscending, filter: filter)
        XCTAssertEqual(first.items.map(\.title), ["Amber Road", "Cedar Lane"])
        XCTAssertTrue(first.hasMore)
        let second = try await client.series(in: category, page: 2, pageSize: 2, sort: .titleAscending, filter: filter)
        XCTAssertEqual(second.items.map(\.title), ["Dune Sea"])
        XCTAssertFalse(second.hasMore)
        let genres = try await client.filterGenres(in: category)
        XCTAssertEqual(genres, ["Comedy", "Drama", "Mystery"])
        XCTAssertTrue(String(decoding: mock.requests.first?.httpBody ?? Data(), as: UTF8.self).contains("status genre"))
    }

    func testKomgaSearchCondition() throws {
        let filter = LibraryFilter(statuses: [.completed, .ongoing], readProgress: .unfinished, genres: ["mystery"])
        let condition = try XCTUnwrap(KomgaClient.condition(library: "LIB", filter: filter))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(condition)) as? [String: Any])
        let all = try XCTUnwrap(json["allOf"] as? [[String: Any]])
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual((all[0]["libraryId"] as? [String: String])?["value"], "LIB")
        let statuses = try XCTUnwrap(all[1]["anyOf"] as? [[String: [String: String]]])
        XCTAssertEqual(statuses.compactMap { $0["seriesStatus"]?["value"] }, ["ENDED", "ONGOING"])
        let reads = try XCTUnwrap(all[2]["anyOf"] as? [[String: [String: String]]])
        XCTAssertEqual(reads.compactMap { $0["readStatus"]?["value"] }, ["UNREAD", "IN_PROGRESS"])
        XCTAssertEqual((all[3]["genre"] as? [String: String])?["value"], "mystery")

        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KomgaClient.condition(library: "LIB", filter: .empty)))
        XCTAssertNotNil((plain as? [String: Any])?["libraryId"], "no filter: just the library")
    }

    func testKomgaSendsFilterAndListsGenres() async throws {
        let mock = MockTransport()
        mock.on("POST", "api/v1/series/list", body: #"{"content":[{"id":"S1","name":"Quiet Pond","booksCount":3}],"last":true}"#)
        mock.on("GET", "api/v1/genres", body: #"["mystery","comedy"]"#)
        let client = KomgaClient(config: ServerConfig(kind: .komga, name: "Komga", baseURL: URL(string: "http://komga.local")!),
                                 apiKey: "KEY", username: nil, password: nil, transport: mock)
        let page = try await client.series(in: category, page: 1, pageSize: 10, sort: .titleAscending,
                                           filter: LibraryFilter(readProgress: .read))
        XCTAssertEqual(page.items.map(\.title), ["Quiet Pond"])
        let body = String(decoding: mock.lastRequest(containing: "api/v1/series/list")?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("readStatus"), body)
        XCTAssertTrue(body.contains("READ"), body)
        let genres = try await client.filterGenres(in: category)
        XCTAssertEqual(genres, ["comedy", "mystery"])
        XCTAssertTrue(mock.lastRequest(containing: "api/v1/genres")?.url?.absoluteString.contains("library_id=1") ?? false)
    }

    func testServersWithoutFiltersIgnoreThem() async throws {
        let opds = MangaServerFactory.make(config: ServerConfig(kind: .opds, name: "O", baseURL: URL(string: "http://o.local")!),
                                           credential: nil)
        XCTAssertEqual(opds.libraryFilterSupport, [])
        let free = MangaServerFactory.make(config: ServerConfig(kind: .freeLibrary, name: "F", baseURL: URL(string: "http://f.local")!),
                                           credential: nil)
        XCTAssertEqual(free.libraryFilterSupport, .genres)
    }

    func testDemoServerFilters() async throws {
        let server = SampleLibraryServer(config: ServerConfig(kind: .kavita, name: "Demo", baseURL: URL(string: "http://demo.local")!),
                                         seriesCount: 30, latency: .zero)
        let all = MangaCategory(id: "all", name: "All Series")
        let hiatus = try await server.series(in: all, page: 1, pageSize: 50, sort: .recentlyAdded,
                                             filter: LibraryFilter(statuses: [.hiatus])).items.map(\.ref.seriesID)
        XCTAssertEqual(hiatus, ["30", "25", "20", "15", "10", "5"])
        server.markAllRead(seriesID: "3")
        let read = try await server.series(in: all, page: 1, pageSize: 50, sort: .titleAscending,
                                           filter: LibraryFilter(readProgress: .read)).items.map(\.ref.seriesID)
        XCTAssertEqual(read, ["3"])
        let comedy = try await server.series(in: all, page: 1, pageSize: 50, sort: .recentlyAdded,
                                             filter: LibraryFilter(genres: ["Comedy"])).items.count
        XCTAssertEqual(comedy, 10)
        let detail = try await server.seriesDetail("5")
        XCTAssertEqual(detail.status, PublicationStatus.hiatus.title)
    }
}
