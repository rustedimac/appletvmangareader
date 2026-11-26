import XCTest
@testable import MangaCore

final class WelcomeTests: XCTestCase {
    /// A fresh install as the app makes it: one profile and the Free Library.
    private func freshInstall() -> (AppState, UUID) {
        var state = AppState.initial()
        state.installFreeLibraryIfNeeded()
        return (state, state.activeProfileID!)
    }

    private var choices: [Welcome.Choice] { Welcome.choices(from: .bundled) }
    private var allIDs: Set<String> { Set(choices.map(\.id)) }

    func testShowsOnFreshInstallUntilStartReading() {
        var (state, p) = freshInstall()
        XCTAssertTrue(Welcome.shouldShow(state, profile: p))
        state.finishWelcome(collections: ["comics"], allCollections: allIDs, profile: p)
        XCTAssertFalse(Welcome.shouldShow(state, profile: p))
        XCTAssertEqual(state.selectedCategories(profile: p, server: FreeLibrary.serverID), ["comics"])
    }

    func testNeverShowsWithAServerOfTheirOwn() {
        var (state, p) = freshInstall()
        state.addServer(ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://k.test")!))
        XCTAssertFalse(Welcome.shouldShow(state, profile: p))
        // Even with the Free Library gone.
        state.removeFreeLibrary()
        XCTAssertFalse(Welcome.shouldShow(state, profile: p))
    }

    func testComesBackWhenEveryLibraryIsGone() {
        var (state, p) = freshInstall()
        state.finishWelcome(collections: ["comics"], allCollections: allIDs, profile: p)
        state.removeFreeLibrary()
        XCTAssertTrue(state.servers.isEmpty)
        XCTAssertTrue(Welcome.shouldShow(state, profile: p))

        state.finishWelcome(collections: ["books"], allCollections: allIDs, profile: p)
        XCTAssertTrue(state.hasFreeLibrary)
        XCTAssertNil(state.freeLibraryRemoved)
        XCTAssertFalse(Welcome.shouldShow(state, profile: p))
        XCTAssertEqual(state.selectedCategories(profile: p, server: FreeLibrary.serverID), ["books"])
    }

    func testEmptyPickOnlyMarksDone() {
        var state = AppState.initial()
        let p = state.activeProfileID!
        state.finishWelcome(collections: [], allCollections: allIDs, profile: p)
        XCTAssertFalse(state.hasFreeLibrary)
        // Still nothing to read, so it shows again.
        XCTAssertTrue(Welcome.shouldShow(state, profile: p))
    }

    func testTickingEverythingSavesAll() {
        var (state, p) = freshInstall()
        state.finishWelcome(collections: allIDs, allCollections: allIDs, profile: p)
        XCTAssertNil(state.selectedCategories(profile: p, server: FreeLibrary.serverID))
    }

    func testIsPerProfile() {
        var (state, p) = freshInstall()
        state.finishWelcome(collections: ["comics"], allCollections: allIDs, profile: p)
        let kid = state.addProfile(name: "Kid").id
        XCTAssertFalse(Welcome.shouldShow(state, profile: p))
        XCTAssertTrue(Welcome.shouldShow(state, profile: kid))
        XCTAssertEqual(Welcome.initialSelection(state, profile: kid, choices: choices), Welcome.suggestedCollections)
    }

    func testProfilesThatAlreadyReadSkipIt() {
        var (state, p) = freshInstall()
        state.recordProgress(SeriesRef(serverID: FreeLibrary.serverID, seriesID: "pepper-and-carrot"),
                             chapterID: "1", page: 2, completed: false, profile: p)
        XCTAssertFalse(Welcome.shouldShow(state, profile: p))

        var (picked, q) = freshInstall()
        picked.setSelectedCategories(["pulps"], profile: q, server: FreeLibrary.serverID)
        XCTAssertFalse(Welcome.shouldShow(picked, profile: q))
    }

    func testInitialSelectionKeepsAnEarlierPick() {
        var (state, p) = freshInstall()
        XCTAssertEqual(Welcome.initialSelection(state, profile: p, choices: choices), ["comics", "webcomics"])
        state.setSelectedCategories(["pulps", "gone"], profile: p, server: FreeLibrary.serverID)
        XCTAssertEqual(Welcome.initialSelection(state, profile: p, choices: choices), ["pulps"])
    }

    func testChoicesComeFromTheCatalog() {
        XCTAssertEqual(choices.map(\.id), ["comics", "books", "pulps", "webcomics"])
        XCTAssertTrue(choices.allSatisfy { !$0.summary.isEmpty && !$0.name.isEmpty })
        XCTAssertEqual(choices.first { $0.id == "pulps" }?.detail, "2 series · 144 issues")
        XCTAssertEqual(choices.first { $0.id == "comics" }?.detail, "4 series")
        XCTAssertTrue(Welcome.suggestedCollections.isSubset(of: allIDs))
    }

    func testDoneFlagPersistsAndSyncs() throws {
        var (state, p) = freshInstall()
        state.finishWelcome(collections: ["comics"], allCollections: allIDs, profile: p)

        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertFalse(Welcome.shouldShow(decoded, profile: p))

        let records = SyncMapper.payloads(from: state).map { key, item in
            SyncRecord(key: key, kind: item.kind, payload: item.payload, modifiedAt: Date(), deviceID: "t")
        }
        XCTAssertTrue(records.contains { $0.kind == .welcome })
        var other = AppState()
        SyncMapper.apply(SyncPatch(records: records), to: &other)
        XCTAssertEqual(other.profileData[p.uuidString]?.welcomeCompleted, true)
        XCTAssertFalse(Welcome.shouldShow(other, profile: p))
    }
}
