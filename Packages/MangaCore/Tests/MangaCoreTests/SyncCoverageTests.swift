import XCTest
@testable import MangaCore

/// Every persisted field must be classified: synced by `SyncMapper`, kept on
/// the device on purpose, or a known sync gap. A new field that is none of
/// these fails here, so whoever adds it decides whether it syncs (and adds a
/// `SyncMapper` domain) instead of it silently staying on one Apple TV.
/// See docs/ICLOUD.md and docs/CONSISTENCY_AUDIT.md.
final class SyncCoverageTests: XCTestCase {
    /// `ProfileData` fields with a `SyncMapper` domain.
    static let syncedProfileFields: Set<String> = [
        "serverSettings", "favorites", "progress", "defaultReaderSettings", "readerOverrides", "browse",
        // Added by the first-run welcome PR (#43) with its own `welcome` kind.
        "welcomeCompleted",
    ]

    /// `ProfileData` fields that stay on this device by design.
    static let localProfileFields: Set<String> = [
        // A cache of titles and covers for the Top Shelf, rebuilt from progress.
        "recentSeries",
        // Profile PIN settings stay out of iCloud (docs/ICLOUD.md, #19).
        "requiresPINToOpen",
    ]

    /// `ProfileData` fields that should sync but have no domain yet.
    /// Remove a field from here when its domain lands.
    static let profileSyncGaps: Set<String> = [
        "bookSettings", "bookmarks", "favoritesSort", "webtoonAutoScrollLevel",
        // Content filters (#19): decide when that PR lands.
        "contentFilter",
    ]

    /// `AppState` top-level fields.
    static let syncedStateFields: Set<String> = ["profiles", "servers", "profileData"]
    static let localStateFields: Set<String> = [
        "version",
        // Which profile is open on this device, and the Apple TV user's
        // remembered profile, are per device.
        "activeProfileID", "rememberedProfileID",
    ]
    static let stateSyncGaps: Set<String> = ["freeLibraryRemoved"]

    func testEveryProfileFieldIsClassified() throws {
        let keys = try jsonKeys(of: Self.fullyPopulatedProfileData())
        let classified = Self.syncedProfileFields.union(Self.localProfileFields).union(Self.profileSyncGaps)
        let unclassified = keys.subtracting(classified)
        XCTAssertTrue(unclassified.isEmpty,
                      "ProfileData fields \(unclassified.sorted()) aren't classified. Add a SyncMapper domain "
                      + "(and list them as synced) or list them as local or as a sync gap in SyncCoverageTests.")
    }

    func testEveryStateFieldIsClassified() throws {
        var state = AppState.initial()
        state.rememberedProfileID = state.activeProfileID
        state.freeLibraryRemoved = true
        let keys = try jsonKeys(of: state)
        let classified = Self.syncedStateFields.union(Self.localStateFields).union(Self.stateSyncGaps)
        let unclassified = keys.subtracting(classified)
        XCTAssertTrue(unclassified.isEmpty,
                      "AppState fields \(unclassified.sorted()) aren't classified in SyncCoverageTests.")
    }

    func testListsDontOverlap() {
        let lists = [Self.syncedProfileFields, Self.localProfileFields, Self.profileSyncGaps]
        for (i, a) in lists.enumerated() {
            for b in lists[(i + 1)...] {
                XCTAssertTrue(a.isDisjoint(with: b), "\(a.intersection(b)) is in two lists")
            }
        }
    }

    /// The fields classified as synced really reach iCloud: a profile with
    /// them set produces records of their kinds.
    func testSyncedProfileFieldsProduceRecords() {
        var state = AppState.initial()
        let p = state.activeProfile!.id
        state.profileData[p.uuidString] = Self.fullyPopulatedProfileData()
        let kinds = Set(SyncMapper.payloads(from: state).values.map { $0.kind })
        for kind in [SyncKind.serverSettings, .favorite, .progress, .readerDefaults, .readerOverride, .browse] {
            XCTAssertTrue(kinds.contains(kind), "no \(kind) record")
        }
    }

    // MARK: Helpers

    static func fullyPopulatedProfileData() -> ProfileData {
        let server = UUID()
        let ref = SeriesRef(serverID: server, seriesID: "1")
        let series = SeriesSummary(ref: ref, title: "Star Harbor", coverURL: nil)
        var data = ProfileData(
            serverSettings: [server.uuidString: ProfileServerSettings(selectedCategoryIDs: ["1"])],
            favorites: [Favorite(series: series, addedAt: Date(timeIntervalSince1970: 1_700_000_000))],
            progress: [ref.storageKey: SeriesProgress(chapterID: "c1", page: 3,
                                                      updatedAt: Date(timeIntervalSince1970: 1_700_000_000))],
            defaultReaderSettings: .default,
            readerOverrides: [ref.storageKey: .default],
            bookSettings: BookSettings(),
            bookmarks: [Bookmark(series: series, chapterID: "c1", chapterTitle: "Chapter 1", page: 2)],
            favoritesSort: FavoritesSort(key: .title, ascending: true),
            recentSeries: [ref.storageKey: series],
            browse: BrowsePreferences())
        data.webtoonAutoScrollLevel = 4
        return data
    }

    private func jsonKeys<T: Encodable>(of value: T) throws -> Set<String> {
        let data = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }
}
