import XCTest
@testable import MangaCore

/// Upgrade safety for everything the app saves on the Apple TV: an app
/// update must never wipe servers, profiles, logins, settings, progress,
/// bookmarks or favorites.
///
/// `Fixtures/SavedData/` holds each saved format exactly as a past build
/// wrote it (fictional titles, generic hosts, fake keys). The tests decode
/// them with today's code and also check, field by field, that:
/// - a field missing from older data falls back to a default instead of
///   failing the whole profile or entry (`testEveryFieldMayBeMissing`),
/// - a value this build doesn't know (an enum case from a newer build, or
///   one that was removed) costs at most that setting, never an entry
///   (`testUnknownValuesDontLoseEntries`),
/// - the newest fixture covers every field the current code saves
///   (`testNewestFixtureCoversEveryField`), so a new field can't ship
///   without a snapshot of the shape before it.
///
/// When you add or change a saved field: copy the newest fixture to a new
/// file named for today, add your field to the copy (as the app would
/// write it), add the file to `SavedFormats.appStateFixtures`, and
/// classify the field in `SyncCoverageTests`. Never edit an existing
/// fixture: it is what users' Apple TVs hold. See docs/UPGRADE_SAFETY.md.
enum SavedFormats {
    /// `AppState` snapshots in files, oldest first. The older, smaller
    /// shapes are inline in `AppStateFixtures`.
    static let appStateFixtures = [
        "appstate-v1-2026-11-26",
        // Adds `showsProgressPercent` to browse (#55).
        "appstate-v1-2026-11-26-percent",
        // Adds `unreadChapters` to series summaries (#74).
        "appstate-v1-2026-11-26-unread-chapters",
        // Adds `alternateURLs` to servers (#34).
        "appstate-v1-2026-11-26-addresses",
    ]
    static var newestAppState: String { appStateFixtures.last! }

    /// Fields every build has always written. Losing one of these loses
    /// the entry that holds it, which salvage then drops on its own (see
    /// `AppStateUpgradeTests`); everything else must be optional.
    static let requiredAppStateFields: Set<String> = [
        // Without the list, salvage rebuilds profiles from their data.
        "profiles", "profiles[].id",
        "servers[].id", "servers[].kind", "servers[].baseURL",
        // A series is identified by its ref.
        "profileData.*.favorites[].series", "profileData.*.favorites[].series.ref",
        "profileData.*.favorites[].series.ref.serverID", "profileData.*.favorites[].series.ref.seriesID",
        "profileData.*.bookmarks[].series", "profileData.*.bookmarks[].series.ref",
        "profileData.*.bookmarks[].series.ref.serverID", "profileData.*.bookmarks[].series.ref.seriesID",
        "profileData.*.bookmarks[].chapterID", "profileData.*.bookmarks[].page",
        "profileData.*.browse.caughtUp[].series", "profileData.*.browse.caughtUp[].series.ref",
        "profileData.*.browse.caughtUp[].series.ref.serverID", "profileData.*.browse.caughtUp[].series.ref.seriesID",
        "profileData.*.progress.*.series.ref", "profileData.*.progress.*.series.ref.serverID",
        "profileData.*.progress.*.series.ref.seriesID",
        "profileData.*.recentSeries.*.ref", "profileData.*.recentSeries.*.ref.serverID",
        "profileData.*.recentSeries.*.ref.seriesID",
        // Where the profile is: without these there is no position.
        "profileData.*.progress.*.chapterID", "profileData.*.progress.*.page",
        "profileData.*.progress.*.pending[].chapterID", "profileData.*.progress.*.pending[].page",
    ]

    /// Values that may be unknown to this build and still lose their entry,
    /// with why.
    static let unknownValueLosses: Set<String> = [
        // A server of a kind this build can't talk to can't be shown. It is
        // only possible after going back to an older build.
        "servers[].kind",
        // Lists of choices: a choice this build doesn't offer is dropped
        // from the list (Home rows come back in their default place).
        "profileData.*.browse.home.order[]", "profileData.*.browse.home.hidden[]",
        "profileData.*.browse.libraries.*.filter.statuses[]",
        "profileData.*.browse.libraryDefaults.filter.statuses[]",
    ]

    /// A different unknown value for each string, so sets keep their size.
    static func unknownValues() -> (Any) -> Any {
        var n = 0
        return { _ in
            n += 1
            return "fromANewerBuild\(n)"
        }
    }
}

final class SavedDataUpgradeTests: XCTestCase {
    typealias F = AppStateFixtures

    // MARK: AppState

    private func decodeState(_ data: Data) throws -> (AppState, AppStateUpgrade.Outcome) {
        try AppStateUpgrade.decode(data)
    }

    private func reencoded(_ state: AppState) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try SavedJSON.parse(encoder.encode(state))
    }

    func testEveryAppStateFixtureLoadsWithoutSalvage() throws {
        for name in SavedFormats.appStateFixtures {
            let data = try SavedJSON.load(name)
            let backing = InMemoryKeyValueStore()
            backing.set(data, forKey: StateStore.key)
            let store = StateStore(backing: backing)
            let state = store.load()
            XCTAssertEqual(store.lastLoad, .decoded, name)
            XCTAssertNil(backing.data(forKey: StateStore.backupKey), name)
            // Nothing in the file is dropped on the way in.
            XCTAssertEqual(SavedJSON.losses(before: try SavedJSON.parse(data), after: try reencoded(state)), [], name)
            // And saving it again keeps it.
            store.save(state)
            XCTAssertEqual(StateStore(backing: backing).load(), state, name)
        }
    }

    /// The newest snapshot names everything stored today, field by field.
    func testNewestAppStateKeepsEverything() throws {
        let (s, outcome) = try decodeState(SavedJSON.load(SavedFormats.newestAppState))
        XCTAssertEqual(outcome, .decoded)
        let me = UUID(uuidString: F.meID)!, kid = UUID(uuidString: F.kidID)!
        let kavita = UUID(uuidString: F.kavitaID)!
        let komga = UUID(uuidString: "5A1D2C3B-CCCC-4E5F-8A9B-00000000000C")!
        let lantern = SeriesRef(serverID: kavita, seriesID: "12")
        let tide = SeriesRef(serverID: komga, seriesID: "k-55")

        XCTAssertEqual(s.profiles.map(\.name), ["Me", "Kid"])
        XCTAssertEqual(s.activeProfileID, kid)
        XCTAssertEqual(s.rememberedProfileID, kid)
        XCTAssertEqual(s.freeLibraryRemoved, true)
        XCTAssertEqual(s.servers.map(\.kind), [.kavita, .suwayomi, .komga, .opds])
        XCTAssertEqual(s.selectedCategories(profile: me, server: komga), ["k1"])

        let favorite = try XCTUnwrap(s.favorites(profile: me).first { $0.series.ref == tide })
        XCTAssertEqual(favorite.unreadChapters, 2)
        XCTAssertEqual(favorite.latestChapterAt, Date(timeIntervalSinceReferenceDate: 785000450))
        XCTAssertEqual(favorite.series.format, .epub)
        XCTAssertEqual(favorite.series.countUnit, .volume)
        XCTAssertEqual(favorite.series.pagesRead, 60)

        let progress = try XCTUnwrap(s.progress(tide, profile: me))
        XCTAssertEqual(progress.chapterID, "v3")
        XCTAssertEqual(progress.page, 11)
        XCTAssertEqual(progress.readChapterIDs, ["v1", "v2"])

        let data = try XCTUnwrap(s.profileData[me.uuidString])
        XCTAssertEqual(data.bookmarks.map(\.page), [11])
        XCTAssertEqual(data.bookmarks.first?.volumeID, "vol-3")
        XCTAssertEqual(data.bookmarks.first?.needsUpload, true)
        XCTAssertEqual(data.bookSettings?.theme, .sepia)
        XCTAssertEqual(data.bookSettings?.columns, 1)
        XCTAssertEqual(data.favoritesSort, FavoritesSort(key: .latestChapter, ascending: true))
        XCTAssertEqual(data.webtoonAutoScrollLevel, 7)
        XCTAssertEqual(data.recentSeries?[tide.storageKey]?.title, "Tidewater Notes")

        let browse = try XCTUnwrap(data.browse)
        XCTAssertEqual(browse.home.serverRows, .perServer)
        XCTAssertEqual(browse.home.hidden, [.newlyAdded])
        XCTAssertEqual(browse.home.order.first, .favorites)
        XCTAssertEqual(browse.gridDensity, .large)
        XCTAssertEqual(browse.posterCaption, .progress)
        XCTAssertFalse(browse.showsProgressPercent)
        let library = browse.options(for: LibraryKey(serverID: kavita, categoryID: "1"))
        XCTAssertEqual(library.sort, .recentlyUpdated)
        XCTAssertEqual(library.filter?.genres, ["Comedy"])
        XCTAssertEqual(library.filter?.statuses, [.ongoing, .hiatus])
        XCTAssertEqual(browse.libraryDefaults.sort, .titleDescending)
        XCTAssertEqual(browse.libraryDefaults.filter.readProgress, .unread)
        XCTAssertEqual(browse.caughtUp.map(\.chapterCount), [9])
        XCTAssertNotNil(browse.dismissedContinueReading[lantern.storageKey])

        let reader = s.readerSettings(for: lantern, profile: me)
        XCTAssertEqual(reader.mode, .webtoon)
        XCTAssertTrue(reader.cropBorders)
        XCTAssertEqual(reader.fit, .width)
        XCTAssertEqual(reader.zoomScale, 3)
        XCTAssertTrue(reader.splitWidePages)
        XCTAssertEqual(reader.picture.color, .grayscale)
        XCTAssertEqual(reader.picture.upscaling, .lanczos)
    }

    /// A field added after this build saved its state is simply absent. Each
    /// field, dropped on its own, must fall back to its default without
    /// changing anything else.
    func testEveryFieldMayBeMissing() throws {
        for name in SavedFormats.appStateFixtures {
            let original = try SavedJSON.parse(SavedJSON.load(name))
            let baseline = try reencoded(decodeState(SavedJSON.data(original)).0)
            for path in SavedJSON.fieldPaths(original).sorted() where !SavedFormats.requiredAppStateFields.contains(path) {
                let dropped = SavedJSON.removing(path, from: original)
                let (state, outcome) = try decodeState(SavedJSON.data(dropped))
                XCTAssertEqual(outcome, .decoded, "\(name): without \(path) the state needs salvage")
                let after = try reencoded(state)
                XCTAssertEqual(try SavedJSON.canonical(SavedJSON.removing(path, from: after)),
                               try SavedJSON.canonical(SavedJSON.removing(path, from: baseline)),
                               "\(name): dropping \(path) changed other saved data")
            }
        }
    }

    /// Enum values (and any other string) this build doesn't recognize may
    /// reset that setting, but never lose a profile, server, favorite,
    /// bookmark or progress entry.
    func testUnknownValuesDontLoseEntries() throws {
        for name in SavedFormats.appStateFixtures {
            let original = try SavedJSON.parse(SavedJSON.load(name))
            for (path, values) in SavedJSON.stringLeaves(original).sorted(by: { $0.key < $1.key }) {
                // Ids are never rewritten by a build.
                guard !values.allSatisfy({ UUID(uuidString: $0) != nil }),
                      !SavedFormats.unknownValueLosses.contains(path) else { continue }
                let changed = SavedJSON.replacing(path, in: original, with: SavedFormats.unknownValues())
                let (state, _) = try decodeState(SavedJSON.data(changed))
                XCTAssertEqual(SavedJSON.losses(before: original, after: try reencoded(state)), [],
                               "\(name): an unknown value at \(path) lost entries")
            }
        }
    }

    /// Fails when the code saves a field the newest fixture doesn't have:
    /// add a new fixture with it (see the top of this file).
    func testNewestFixtureCoversEveryField() throws {
        let data = try SavedJSON.load(SavedFormats.newestAppState)
        let (state, _) = try decodeState(data)
        let unset = FieldPresence.unsetFields(in: state)
        XCTAssertEqual(unset, [], "Fields \(unset.sorted()) aren't set anywhere in \(SavedFormats.newestAppState). "
                       + "Add a fixture of today's saved state that sets them (see SavedDataUpgradeTests).")
        let written = SavedJSON.fieldPaths(try reencoded(state))
        let missing = written.subtracting(SavedJSON.fieldPaths(try SavedJSON.parse(data)))
        XCTAssertEqual(missing, [], "The app now saves \(missing.sorted()), which no fixture has. "
                       + "Add a fixture of today's saved state (see SavedDataUpgradeTests).")
    }

    // MARK: Other saved data

    /// Servers shared by every Apple TV user (user-independent keychain).
    /// If this can't be read, the next launch writes an empty directory
    /// over it, dropping every other user's servers and logins.
    func testSharedServerDirectory() throws {
        // v2 adds `alternateURLs` (#34); v1 must still load the same servers.
        try checkFormat("shared-servers-v2", as: SharedServerDirectory.self,
                        required: ["servers[].id", "servers[].kind", "servers[].baseURL"],
                        unknownLosses: ["servers[].kind"])
        let v1 = try JSONDecoder().decode(SharedServerDirectory.self, from: SavedJSON.load("shared-servers-v1"))
        let dir = try JSONDecoder().decode(SharedServerDirectory.self, from: SavedJSON.load("shared-servers-v2"))
        XCTAssertEqual(v1.servers.map(\.id), dir.servers.map(\.id))
        XCTAssertEqual(v1.servers.first?.alternateURLs, [])
        XCTAssertEqual(dir.servers.first?.alternateURLs, [URL(string: "https://kavita.example.org")!])
        XCTAssertEqual(dir.servers.map(\.kind), [.kavita, .suwayomi, .komga])
        XCTAssertEqual(dir.removedServerIDs.count, 1)
        XCTAssertEqual(dir.credential(for: UUID(uuidString: F.kavitaID)!)?.apiKey, "fixture-kavita-key")
        XCTAssertEqual(dir.credential(for: UUID(uuidString: F.suwayomiID)!)?.suwayomiLogin, .token)
    }

    func testSharedServerDirectoryKeepsGoodServersNextToABadOne() throws {
        let original = try SavedJSON.parse(SavedJSON.load("shared-servers-v1"))
        let damaged = SavedJSON.replacing("servers[].baseURL", in: original) { value in
            (value as? String) == "http://suwayomi.local:4567" ? 42 : value
        }
        let dir = try JSONDecoder().decode(SharedServerDirectory.self, from: SavedJSON.data(damaged))
        XCTAssertEqual(dir.servers.map(\.kind), [.kavita, .komga])
        XCTAssertEqual(dir.credentials.count, 2)
    }

    /// Logins (keychain). Never shown in a fixture with real values.
    func testCredentials() throws {
        try checkFormat("credentials-v1", as: [ServerCredential].self, required: [], unknownLosses: [])
        let logins = try JSONDecoder().decode([ServerCredential].self, from: SavedJSON.load("credentials-v1"))
        XCTAssertEqual(logins.first?.apiKey, "fixture-kavita-key")
        XCTAssertEqual(logins.last?.suwayomiLogin, .basic)
    }

    /// Where each book was left inside a section.
    func testBookPositions() throws {
        try checkFormat("book-positions-v1", as: [String: BookPosition].self,
                        required: ["*.section"], unknownLosses: [], via: BookPositionStore.decode)
        let backing = InMemoryKeyValueStore()
        backing.set(try SavedJSON.load("book-positions-v1"), forKey: BookPositionStore.key)
        let store = BookPositionStore(backing: backing)
        let me = UUID(uuidString: F.meID)!
        let chapter = Chapter(id: "v3", seriesRef: SeriesRef(serverID: UUID(uuidString: "5A1D2C3B-CCCC-4E5F-8A9B-00000000000C")!,
                                                            seriesID: "k-55"), title: "Volume 3", number: 3, pageCount: 20)
        XCTAssertEqual(store.position(profile: me, chapter: chapter)?.fraction, 0.375)
    }

    func testOneBadBookPositionCostsOnlyThatOne() throws {
        let original = try SavedJSON.parse(SavedJSON.load("book-positions-v1"))
        guard var object = original as? [String: Any] else { return XCTFail("not an object") }
        object["junk"] = ["section": "not a number"]
        let positions = BookPositionStore.decode(try SavedJSON.data(object))
        XCTAssertEqual(positions.count, 2)
    }

    /// The iCloud offline queue: changes not yet uploaded.
    func testSyncJournal() throws {
        try checkFormat("sync-journal-v1", as: SyncJournal.self,
                        required: ["pending.*.key", "pending.*.kind", "deviceID"],
                        // Opaque bytes, not a value a build interprets.
                        unknownLosses: ["pending.*.payload"])
        let journal = try JSONDecoder().decode(SyncJournal.self, from: SavedJSON.load("sync-journal-v1"))
        XCTAssertEqual(journal.deviceID, "7C0FFEE0-0000-4000-8000-000000000001")
        XCTAssertEqual(journal.pending.count, 4)
        XCTAssertTrue(journal.pending.values.contains { $0.isDeleted })
    }

    /// A backup file from this version restores into a fresh install.
    func testBackupRestoresIntoAFreshInstall() throws {
        let records = try MangaBackup.parse(SavedJSON.load("backup-v1"))
        XCTAssertFalse(records.isEmpty)
        let (saved, _) = try decodeState(SavedJSON.load(SavedFormats.newestAppState))
        var fresh = AppState.initial()
        let patch = MangaBackup.restorePatch(state: fresh, backup: records)
        SyncMapper.apply(patch, to: &fresh)

        XCTAssertEqual(Set(fresh.servers.map(\.id)), Set(saved.servers.map(\.id)))
        XCTAssertTrue(Set(saved.profiles.map(\.name)).isSubset(of: Set(fresh.profiles.map(\.name))))
        for profile in saved.profiles {
            guard let restored = fresh.profiles.first(where: { $0.name == profile.name }) else { continue }
            let before = saved.profileData[profile.id.uuidString] ?? ProfileData()
            let after = fresh.profileData[restored.id.uuidString] ?? ProfileData()
            XCTAssertEqual(Set(after.favorites.map(\.series.ref)), Set(before.favorites.map(\.series.ref)), profile.name)
            for (key, p) in before.progress {
                XCTAssertEqual(after.progress[key]?.chapterID, p.chapterID, "\(profile.name) \(key)")
                XCTAssertEqual(after.progress[key]?.page, p.page, "\(profile.name) \(key)")
                XCTAssertTrue(p.readChapterIDs.isSubset(of: after.progress[key]?.readChapterIDs ?? []), key)
            }
            XCTAssertEqual(after.readerOverrides.keys.sorted(), before.readerOverrides.keys.sorted(), profile.name)
            XCTAssertEqual(after.browse?.home, before.browse?.home, profile.name)
        }
    }

    // MARK: Helpers

    /// The three field checks of the `AppState` tests for another saved
    /// format: it loads, a missing field falls back, an unknown value
    /// loses nothing else.
    private func checkFormat<T: Codable>(_ name: String, as type: T.Type, required: Set<String>,
                                         unknownLosses: Set<String>,
                                         via decode: ((Data) -> T?)? = nil,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
        let decodeValue: (Data) -> T? = decode ?? { try? JSONDecoder().decode(T.self, from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func reencode(_ value: T) throws -> Any { try SavedJSON.parse(encoder.encode(value)) }

        let original = try SavedJSON.parse(SavedJSON.load(name))
        let value = try XCTUnwrap(decodeValue(try SavedJSON.data(original)), "\(name) doesn't load", file: file, line: line)
        let baseline = try reencode(value)
        XCTAssertEqual(SavedJSON.losses(before: original, after: baseline), [], name, file: file, line: line)
        let unset = FieldPresence.unsetFields(in: value)
        XCTAssertEqual(unset, [], "\(name) doesn't set \(unset.sorted()): add a newer fixture", file: file, line: line)

        for path in SavedJSON.fieldPaths(original).sorted() where !required.contains(path) {
            let dropped = SavedJSON.removing(path, from: original)
            guard let after = decodeValue(try SavedJSON.data(dropped)) else {
                XCTFail("\(name) doesn't load without \(path)", file: file, line: line)
                continue
            }
            XCTAssertEqual(try SavedJSON.canonical(SavedJSON.removing(path, from: reencode(after))),
                           try SavedJSON.canonical(SavedJSON.removing(path, from: baseline)),
                           "\(name): dropping \(path) changed other saved data", file: file, line: line)
        }
        for (path, values) in SavedJSON.stringLeaves(original) {
            guard !values.allSatisfy({ UUID(uuidString: $0) != nil }), !unknownLosses.contains(path) else { continue }
            let changed = SavedJSON.replacing(path, in: original, with: SavedFormats.unknownValues())
            guard let after = decodeValue(try SavedJSON.data(changed)) else {
                XCTFail("\(name) doesn't load with an unknown value at \(path)", file: file, line: line)
                continue
            }
            XCTAssertEqual(SavedJSON.losses(before: original, after: try reencode(after)), [],
                           "\(name): an unknown value at \(path) lost entries", file: file, line: line)
        }
    }
}
