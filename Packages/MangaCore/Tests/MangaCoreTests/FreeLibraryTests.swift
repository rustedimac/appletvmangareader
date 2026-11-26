import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

func freeLibraryFixture(_ name: String) -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/FreeLibrary"),
          let text = try? String(contentsOf: url, encoding: .utf8) else {
        XCTFail("Missing fixture \(name)")
        return ""
    }
    return text
}

final class FreeLibraryTests: XCTestCase {
    private func makeStore(_ catalog: FreeLibraryCatalog = .bundled, remote: URL? = nil) -> FreeLibraryStore {
        FreeLibraryStore(bundled: catalog, remoteURL: remote, cacheFile: nil)
    }

    private func client(transport: MockTransport = MockTransport(), scope: Set<String>? = nil,
                        catalog: FreeLibraryCatalog = .bundled) -> FreeLibraryClient {
        FreeLibraryClient(categoryScope: scope, transport: transport, store: makeStore(catalog))
    }

    private var sampleCatalog: FreeLibraryCatalog {
        FreeLibraryCatalog(schema: 1, version: 3, updated: "2026-11-25",
            collections: [.init(id: "comics", name: "Classic Comics"), .init(id: "books", name: "Illustrated Books"),
                          .init(id: "webcomics", name: "Webcomics"), .init(id: "unused", name: "Unused")],
            series: [
                .init(id: "nemo", title: "Little Nemo", creators: ["Winsor McCay"], published: "1905–1914",
                      collection: "comics", synopsis: "Dreams.", genres: ["Fantasy"], license: .publicDomainUS,
                      rights: "Published in the US before 1931.", source: .internetArchive, cover: nil,
                      chapters: [.init(identifier: "LittleNemo1905-1914ByWinsorMccay", title: "1905–1914", pages: 421)],
                      added: "2026-11-20"),
                .init(id: "alice", title: "Alice's Adventures in Wonderland", creators: ["Lewis Carroll", "John Tenniel"],
                      published: "1894", collection: "books", synopsis: "Down the rabbit hole.", genres: nil,
                      license: .publicDomainUS, rights: "Published in 1894.", source: .internetArchive,
                      cover: "aliceCover", chapters: [.init(identifier: "alicesadventwond00carrrich", title: "Book", pages: nil)],
                      added: "2026-11-25"),
                .init(id: "pepper", title: "Pepper&Carrot", creators: ["David Revoy"], published: "2014–",
                      collection: "webcomics", synopsis: "A young witch and her cat.", genres: nil, license: .ccBy4,
                      rights: "CC BY 4.0.", source: .pepperCarrot, cover: nil, chapters: nil, added: "2026-11-20"),
            ])
    }

    // MARK: Catalog

    func testBundledCatalogIsValid() {
        let catalog = FreeLibraryCatalog.bundled
        XCTAssertEqual(catalog.problems, [])
        XCTAssertFalse(catalog.series.isEmpty)
        XCTAssertTrue(catalog.series.contains { $0.source == .pepperCarrot })
        for s in catalog.series where s.source == .internetArchive {
            XCTAssertEqual(s.license, .publicDomainUS, s.id)
        }
    }

    /// Every Internet Archive entry must say why it's free, and be dated 1930 or earlier.
    func testBundledInternetArchiveEntriesArePre1931() {
        for s in FreeLibraryCatalog.bundled.series where s.source == .internetArchive {
            let years = s.published.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 1000 }
            XCTAssertFalse(years.isEmpty, "\(s.id) has no year")
            XCTAssertTrue(years.allSatisfy { $0 <= 1930 }, "\(s.id) published \(s.published)")
        }
    }

    func testProblemsCatchUnsafeEntries() {
        var catalog = sampleCatalog
        XCTAssertEqual(catalog.problems, [])
        catalog.series[0].license = .ccBy4
        catalog.series[1].chapters = [.init(identifier: "../evil?x=1", title: "x", pages: nil)]
        catalog.series[2].collection = "nope"
        XCTAssertEqual(catalog.problems.count, 3)
        catalog.schema = 2
        XCTAssertTrue(catalog.problems.contains("unsupported schema 2"))
    }

    func testIdentifierValidation() {
        XCTAssertTrue(FreeLibraryCatalog.isValidIdentifier("Weird_Tales_v01n01_1923-03"))
        XCTAssertFalse(FreeLibraryCatalog.isValidIdentifier(""))
        XCTAssertFalse(FreeLibraryCatalog.isValidIdentifier("a/b"))
        XCTAssertFalse(FreeLibraryCatalog.isValidIdentifier("a b"))
        XCTAssertFalse(FreeLibraryCatalog.isValidIdentifier("évil"))
    }

    func testRemoteCatalogReplacesBundledOnlyWhenValidAndNotOlder() async throws {
        let remote = URL(string: "https://raw.example/catalog.json")!
        let transport = MockTransport()
        var newer = sampleCatalog
        newer.version = 4
        newer.series.removeLast()
        transport.on("GET", "raw.example", body: String(decoding: try JSONEncoder().encode(newer), as: UTF8.self))
        let store = makeStore(sampleCatalog, remote: remote)
        await store.refresh(transport: transport)
        let afterNewer = await store.catalog(transport: transport)
        XCTAssertEqual(afterNewer.version, 4)
        XCTAssertEqual(afterNewer.series.count, 2)

        // Older or invalid catalogs are ignored.
        var older = sampleCatalog
        older.version = 1
        var invalid = sampleCatalog
        invalid.version = 9
        invalid.series[0].license = .ccBy4
        for bad in [older, invalid] {
            let t = MockTransport()
            t.on("GET", "raw.example", body: String(decoding: try JSONEncoder().encode(bad), as: UTF8.self))
            let s = makeStore(sampleCatalog, remote: remote)
            await s.refresh(transport: t)
            let kept = await s.catalog(transport: t)
            XCTAssertEqual(kept.version, 3)
        }

        // Network failure keeps the bundled copy.
        let failing = MockTransport()
        failing.on("GET", "raw.example", status: 500, body: "")
        let s = makeStore(sampleCatalog, remote: remote)
        await s.refresh(transport: failing)
        let kept = await s.catalog(transport: failing)
        XCTAssertEqual(kept, sampleCatalog)
    }

    func testRemoteCatalogIsSavedAndReloadedFromCache() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fl-\(UUID().uuidString)/catalog.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var newer = sampleCatalog
        newer.version = 7
        let transport = MockTransport()
        transport.on("GET", "raw.example", body: String(decoding: try JSONEncoder().encode(newer), as: UTF8.self))
        let store = FreeLibraryStore(bundled: sampleCatalog, remoteURL: URL(string: "https://raw.example/c.json")!, cacheFile: file)
        await store.refresh(transport: transport)
        let reopened = FreeLibraryStore(bundled: sampleCatalog, remoteURL: nil, cacheFile: file)
        let catalog = await reopened.catalog(transport: transport)
        XCTAssertEqual(catalog.version, 7)
    }

    // MARK: Browsing

    func testCategoriesSkipEmptyCollectionsAndFollowScope() async throws {
        let all = try await client(catalog: sampleCatalog).categories()
        XCTAssertEqual(all.map(\.id), ["comics", "books", "webcomics"])
        let scoped = try await client(scope: ["books"], catalog: sampleCatalog).categories()
        XCTAssertEqual(scoped.map(\.id), ["books"])
    }

    func testSeriesInCategoryPagesAndSorts() async throws {
        let c = client(catalog: sampleCatalog)
        let page = try await c.series(in: MangaCategory(id: "comics", name: "Classic Comics"), page: 1, pageSize: 10)
        XCTAssertEqual(page.items.map(\.title), ["Little Nemo"])
        XCTAssertFalse(page.hasMore)
        let summary = try XCTUnwrap(page.items.first)
        XCTAssertEqual(summary.ref, SeriesRef(serverID: FreeLibrary.serverID, seriesID: "nemo"))
        XCTAssertEqual(summary.libraryID, "comics")
        XCTAssertEqual(summary.coverURL?.absoluteString, "https://archive.org/services/img/LittleNemo1905-1914ByWinsorMccay")
    }

    func testCoverUsesExplicitIdentifierAndPepperCarrotCover() async throws {
        let c = client(catalog: sampleCatalog)
        let results = try await c.search("a")
        let alice = try XCTUnwrap(results.first { $0.ref.seriesID == "alice" })
        XCTAssertEqual(alice.coverURL?.absoluteString, "https://archive.org/services/img/aliceCover")
        let pepper = try XCTUnwrap(results.first { $0.ref.seriesID == "pepper" })
        XCTAssertEqual(pepper.coverURL?.host, "www.peppercarrot.com")
    }

    func testFeeds() async throws {
        let c = client(catalog: sampleCatalog)
        let continueReading = try await c.feed(.continueReading, limit: 10)
        XCTAssertEqual(continueReading, [])
        let updated = try await c.feed(.recentlyUpdated, limit: 10)
        XCTAssertEqual(updated.map(\.ref.seriesID), ["pepper"])
        let added = try await c.feed(.newlyAdded, limit: 2)
        XCTAssertEqual(added.map(\.ref.seriesID), ["alice", "nemo"])
        let scoped = try await client(scope: ["comics"], catalog: sampleCatalog).feed(.newlyAdded, limit: 10)
        XCTAssertEqual(scoped.map(\.ref.seriesID), ["nemo"])
    }

    func testSearchMatchesTitleAndCreatorIgnoringCaseAndAccents() async throws {
        let c = client(catalog: sampleCatalog)
        let byCreator = try await c.search("mccay")
        XCTAssertEqual(byCreator.map(\.ref.seriesID), ["nemo"])
        let byAccent = try await c.search("WONDÉRLAND")
        XCTAssertEqual(byAccent.map(\.ref.seriesID), ["alice"])
        let empty = try await c.search("   ")
        XCTAssertEqual(empty, [])
    }

    func testValidateDescribesCatalog() async throws {
        let text = try await client(catalog: sampleCatalog).validate()
        XCTAssertEqual(text, "3 free titles")
    }

    // MARK: Internet Archive

    func testInternetArchiveDetailCarriesRightsAndChapters() async throws {
        let detail = try await client(catalog: sampleCatalog).seriesDetail("nemo")
        XCTAssertEqual(detail.authors, ["Winsor McCay"])
        XCTAssertEqual(detail.status, "Public domain in the US · 1905–1914")
        XCTAssertTrue(detail.synopsis?.contains("Published in the US before 1931.") ?? false)
        XCTAssertTrue(detail.synopsis?.contains("Internet Archive") ?? false)
        XCTAssertEqual(detail.chapters.map(\.id), ["ia:LittleNemo1905-1914ByWinsorMccay"])
        XCTAssertEqual(detail.chapters.first?.pageCount, 421)
    }

    func testUnknownSeriesIsNotFound() async {
        do {
            _ = try await client(catalog: sampleCatalog).seriesDetail("missing")
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? MangaError, .notFound)
        }
    }

    func testIIIFPagesFromRecordedManifest() async throws {
        let transport = MockTransport()
        transport.on("GET", "iiif.archive.org/iiif/3/LittleNemo1905-1914ByWinsorMccay/manifest.json",
                     body: freeLibraryFixture("ia_littlenemo_manifest"))
        let c = client(transport: transport, catalog: sampleCatalog)
        let chapter = try await c.seriesDetail("nemo").chapters[0]
        let pages = try await c.pages(for: chapter)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages.map(\.index), [0, 1, 2])
        XCTAssertEqual(pages[0].size, PageSize(width: 1740, height: 2376))
        XCTAssertEqual(pages[0].url.absoluteString,
                       "https://iiif.archive.org/image/iiif/3/LittleNemo1905-1914ByWinsorMccay%2Flittle-nemo_jp2.zip%2Flittle-nemo_jp2%2Flittle-nemo_0000.jp2/full/max/0/default.jpg")

        // A second open comes from the cache.
        _ = try await c.pages(for: chapter)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testIIIFLimitsWidthOfLargeScans() throws {
        let manifest = try JSONDecoder().decode(IIIFManifest.self, from: Data("""
            {"type": "Manifest", "items": [{"width": 4412, "height": 6429, "items": [{"items": [{"body":
              {"type": "Image", "service": {"@id": "https://iiif.archive.org/image/iiif/3/big"}}}]}]}]}
            """.utf8))
        let page = try XCTUnwrap(manifest.pages().first)
        XCTAssertEqual(page.size, PageSize(width: 4412, height: 6429))
        XCTAssertEqual(page.url.absoluteString, "https://iiif.archive.org/image/iiif/3/big/full/\(IIIFManifest.sizeParameter(canvasWidth: 4412))/0/default.jpg")
    }

    func testIIIFDropsNonArchiveImages() throws {
        let manifest = try JSONDecoder().decode(IIIFManifest.self, from: Data("""
            {"items": [{"width": 10, "height": 20, "items": [{"items": [{"body": {"id": "https://evil.example/x.jpg"}}]}]},
                       {"width": 10, "height": 20, "items": [{"items": [{"body": {"id": "http://archive.org/x.jpg"}}]}]},
                       {"width": 10, "height": 20, "items": [{"items": [{"body": {"id": "https://ia800.us.archive.org/x.jpg"}}]}]}]}
            """.utf8))
        XCTAssertEqual(manifest.pages().map(\.url.host), ["ia800.us.archive.org"])
    }

    func testEmptyManifestIsAnError() async {
        let transport = MockTransport()
        transport.on("GET", "manifest.json", body: #"{"type": "Manifest", "items": []}"#)
        let c = client(transport: transport, catalog: sampleCatalog)
        do {
            _ = try await c.pages(for: Chapter(id: "ia:LittleNemo1905-1914ByWinsorMccay",
                                               seriesRef: SeriesRef(serverID: FreeLibrary.serverID, seriesID: "nemo"),
                                               title: "x", number: 1, pageCount: 0))
            XCTFail("expected an error")
        } catch {}
    }

    // MARK: Pepper&Carrot

    func testPepperCarrotEpisodesFromRecordedList() async throws {
        let transport = MockTransport()
        transport.on("GET", "peppercarrot.com/0_sources/episodes.json", body: freeLibraryFixture("peppercarrot_episodes"))
        let c = client(transport: transport, catalog: sampleCatalog)
        let detail = try await c.seriesDetail("pepper")
        XCTAssertEqual(detail.chapters.map(\.title), ["Episode 1: Potion of Flight", "Episode 2: Rainbow potions"])
        XCTAssertEqual(detail.chapters.map(\.id), ["pc:ep01_Potion-of-Flight", "pc:ep02_Rainbow-potions"])
        XCTAssertEqual(detail.chapters.map(\.pageCount), [5, 7])
        XCTAssertTrue(detail.synopsis?.contains("David Revoy") ?? false)
        XCTAssertTrue(detail.synopsis?.contains("CC BY 4.0") ?? false)
        XCTAssertEqual(detail.status, "CC BY 4.0 · 2014–")

        let pages = try await c.pages(for: detail.chapters[0])
        XCTAssertEqual(pages.count, 5)
        XCTAssertEqual(pages[0].url.absoluteString,
                       "https://www.peppercarrot.com/0_sources/ep01_Potion-of-Flight/low-res/en_Pepper-and-Carrot_by-David-Revoy_E01P00.jpg")
        XCTAssertEqual(pages[4].url.lastPathComponent, "en_Pepper-and-Carrot_by-David-Revoy_E01P04.jpg")
        XCTAssertNil(pages[0].size)
        // The episode list was fetched once.
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "episodes.json" }.count, 1)
    }

    func testPepperCarrotSkipsUntranslatedAndOddEntries() throws {
        let data = Data("""
            [{"name": "ep10_Summer-Special", "total_pages": 6, "translated_languages": ["en"]},
             {"name": "ep03_The-secret-ingredients", "total_pages": 8, "translated_languages": ["fr"]},
             {"name": "../etc", "total_pages": 3, "translated_languages": ["en"]},
             {"name": "ep08_Pepper-s-Birthday-Party", "total_pages": 7, "translated_languages": ["en"]}]
            """.utf8)
        let episodes = try PepperCarrot.parseEpisodes(data)
        XCTAssertEqual(episodes.map(\.number), [8, 10])
        XCTAssertEqual(episodes[0].title, "Pepper's Birthday Party")
        XCTAssertEqual(episodes[1].pageURL(6)?.lastPathComponent, "en_Pepper-and-Carrot_by-David-Revoy_E10P06.jpg")
    }

    func testDemoTransportServesManifestsAndEpisodes() async throws {
        let c = FreeLibraryClient(transport: FreeLibraryDemoTransport(pagesPerItem: 4), store: makeStore(sampleCatalog))
        let nemo = try await c.seriesDetail("nemo")
        let pages = try await c.pages(for: nemo.chapters[0])
        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages[0].size, PageSize(width: 1600, height: 2400))
        let pepper = try await c.seriesDetail("pepper")
        XCTAssertEqual(pepper.chapters.count, 2)
    }

    func testSaveProgressIsANoOp() async throws {
        let transport = MockTransport()
        let c = client(transport: transport, catalog: sampleCatalog)
        try await c.saveProgress(chapter: Chapter(id: "ia:x", seriesRef: SeriesRef(serverID: FreeLibrary.serverID, seriesID: "nemo"),
                                                  title: "x", number: 1, pageCount: 1),
                                 libraryID: nil, page: 3, completed: false)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testFactoryMakesFreeLibraryClient() {
        let client = MangaServerFactory.make(config: FreeLibrary.config, credential: nil)
        XCTAssertTrue(client is FreeLibraryClient)
    }

    // MARK: App state

    func testInstallRemoveRestore() {
        var state = AppState.initial()
        XCTAssertTrue(state.installFreeLibraryIfNeeded())
        XCTAssertTrue(state.hasFreeLibrary)
        XCTAssertFalse(state.installFreeLibraryIfNeeded(), "only once")
        let profile = state.activeProfileID!
        XCTAssertFalse(state.serverSettings(profile: profile, server: FreeLibrary.serverID).syncProgressToServer)

        // User servers go before the Free Library.
        let kavita = ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://k")!)
        state.addServer(kavita)
        XCTAssertEqual(state.servers.map(\.kind), [.kavita, .freeLibrary])

        state.removeFreeLibrary()
        XCTAssertFalse(state.hasFreeLibrary)
        XCTAssertFalse(state.installFreeLibraryIfNeeded(), "stays removed across launches")
        state.restoreFreeLibrary()
        XCTAssertTrue(state.hasFreeLibrary)
        XCTAssertEqual(state.servers.last?.id, FreeLibrary.serverID)
    }

    func testOldStateWithoutTheFlagDecodes() throws {
        var state = AppState.initial()
        state.installFreeLibraryIfNeeded()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json["freeLibraryRemoved"] = nil
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.freeLibraryRemoved)
        XCTAssertTrue(decoded.hasFreeLibrary)
    }

    func testNewProfilesDontSyncToFreeLibrary() {
        var state = AppState.initial()
        state.installFreeLibraryIfNeeded()
        let kid = state.addProfile(name: "Kid")
        XCTAssertFalse(state.serverSettings(profile: kid.id, server: FreeLibrary.serverID).syncProgressToServer)
    }

    func testReaderDefaultsAreLeftToRight() {
        var base = ReaderSettings.default
        base.direction = .rightToLeft
        XCTAssertEqual(FreeLibrary.readerSettings(from: base).direction, .leftToRight)
        var state = AppState.initial()
        let ref = SeriesRef(serverID: FreeLibrary.serverID, seriesID: "nemo")
        XCTAssertFalse(state.hasReaderOverride(for: ref, profile: state.activeProfileID!))
        state.setReaderSettings(base, for: ref, profile: state.activeProfileID!)
        XCTAssertTrue(state.hasReaderOverride(for: ref, profile: state.activeProfileID!))
    }

    func testServerKindLists() {
        XCTAssertEqual(ServerKind.userAddable, [.kavita, .komga, .suwayomi, .opds])
        XCTAssertFalse(ServerKind.userAddable.contains(.freeLibrary))
        XCTAssertEqual(ServerKind.freeLibrary.categoryNoun, "Collections")
        XCTAssertNil(ServerDraft(kind: .freeLibrary).credential)
    }

    // MARK: Series detail placement and merged Home rows

    func testDetailNamesTheCollectionAndNewlyAddedHasDates() async throws {
        let c = client(catalog: sampleCatalog)
        let nemo = try await c.seriesDetail("nemo")
        XCTAssertEqual(nemo.placement, SeriesPlacement(categories: ["Classic Comics"]))
        let added = try await c.feed(.newlyAdded, limit: 10)
        XCTAssertEqual(added.first?.ref.seriesID, "alice")
        XCTAssertEqual(added.first?.feedDate, FreeLibraryClient.addedDate("2026-11-25"))
        XCTAssertNotNil(FreeLibraryClient.addedDate("2026-11-25"))
        XCTAssertNil(FreeLibraryClient.addedDate("soon"))
    }
}
