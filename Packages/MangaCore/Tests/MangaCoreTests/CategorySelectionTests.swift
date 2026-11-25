import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class CategorySelectionTests: XCTestCase {
    let cats = [MangaCategory(id: "3", name: "Webtoons", order: 1),
                MangaCategory(id: "1", name: "Manga", order: 0),
                MangaCategory(id: "7", name: "Comics", order: 2)]

    func testNilSavedSelectsEverything() {
        let s = CategorySelection(available: cats, saved: nil)
        XCTAssertEqual(s.available.map(\.id), ["1", "3", "7"])
        XCTAssertTrue(s.allSelected)
        XCTAssertNil(s.storedValue, "all ticked stores nil so new libraries show up too")
        XCTAssertEqual(s.summary(kind: .kavita), "All 3 libraries")
    }

    func testSavedSelectionDropsIdsNoLongerOnServer() {
        let s = CategorySelection(available: cats, saved: ["1", "99"])
        XCTAssertEqual(s.selected, ["1"])
        XCTAssertEqual(s.storedValue, ["1"])
        XCTAssertEqual(s.summary(kind: .suwayomi), "1 of 3 categories")
    }

    func testToggleAndCanSave() {
        var s = CategorySelection(available: cats, saved: nil)
        s.toggle("3")
        XCTAssertFalse(s.isSelected("3"))
        XCTAssertEqual(s.storedValue, ["1", "7"])
        s.toggle("unknown")
        XCTAssertEqual(s.selected, ["1", "7"])
        s.selectNone()
        XCTAssertFalse(s.canSave)
        s.set("7", true)
        XCTAssertTrue(s.canSave)
        XCTAssertEqual(s.storedValue, ["7"])
        s.selectAll()
        XCTAssertNil(s.storedValue)
    }

    func testEmptyServerCanStillSave() {
        let s = CategorySelection(available: [], saved: nil)
        XCTAssertTrue(s.canSave)
        XCTAssertEqual(s.summary(kind: .kavita), "No libraries")
    }

    func testServerSettingsIncludes() {
        let all = ProfileServerSettings()
        XCTAssertTrue(all.includes(categories: ["5"]))
        let some = ProfileServerSettings(selectedCategoryIDs: ["1", "2"])
        XCTAssertTrue(some.includes(categories: ["2", "9"]))
        XCTAssertFalse(some.includes(categories: ["9"]))
        XCTAssertTrue(some.includes(categories: nil), "unknown membership is shown")
        let ref = SeriesRef(serverID: UUID(), seriesID: "1")
        XCTAssertTrue(some.includes(SeriesSummary(ref: ref, title: "K", coverURL: nil, libraryID: "1")))
        XCTAssertFalse(some.includes(SeriesSummary(ref: ref, title: "S", coverURL: nil, categoryIDs: ["0"])))
    }

    func testScopedDedupesAndFilters() {
        let id = UUID()
        func s(_ n: String, _ lib: String) -> SeriesSummary {
            SeriesSummary(ref: SeriesRef(serverID: id, seriesID: n), title: n, coverURL: nil, libraryID: lib)
        }
        let list = [s("1", "a"), s("2", "b"), s("1", "a"), s("3", "a")]
        XCTAssertEqual(list.scoped(to: ["a"]).map(\.title), ["1", "3"])
        XCTAssertEqual(list.scoped(to: nil).map(\.title), ["1", "2", "3"])
        XCTAssertEqual(list.scoped(to: []).map(\.title), [])
    }
}
