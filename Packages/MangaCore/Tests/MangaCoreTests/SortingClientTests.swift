import XCTest
@testable import MangaCore

/// Natural ordering inside the Kavita and Suwayomi clients. Names are
/// made up for the tests.
final class SortingClientTests: XCTestCase {
    private let ref = SeriesRef(serverID: UUID(), seriesID: "1")

    func testKavitaSpecialsWithSameSortOrderUseNaturalNames() {
        let specials = KavitaVolumeDTO(id: 9, minNumber: KavitaClient.specialVolumeNumber, name: "Specials", chapters: [
            KavitaChapterDTO(id: 93, range: "Side Story 10", minNumber: 0, sortOrder: 0, pages: 5, isSpecial: true,
                             title: "Side Story 10"),
            KavitaChapterDTO(id: 91, range: "Side Story 2", minNumber: 0, sortOrder: 0, pages: 5, isSpecial: true,
                             title: "Side Story 2"),
            KavitaChapterDTO(id: 92, range: "Side Story [3]", minNumber: 0, sortOrder: 0, pages: 5, isSpecial: true,
                             title: "Side Story 3"),
        ])
        let volume = KavitaVolumeDTO(id: 1, minNumber: 1, name: "1", chapters: [
            KavitaChapterDTO(id: 12, range: "2", minNumber: 2, sortOrder: 2, pages: 10),
            KavitaChapterDTO(id: 11, range: "1", minNumber: 1, sortOrder: 1, pages: 10),
        ])
        let chapters = KavitaClient.chapters(from: [specials, volume], seriesRef: ref)
        XCTAssertEqual(chapters.map(\.id), ["11", "12", "91", "92", "93"])
    }

    func testKavitaLooseVolumesTieBrokenByName() {
        let loose = KavitaClient.looseLeafVolumeNumber
        let a = KavitaVolumeDTO(id: 5, minNumber: loose, name: "Book 10", chapters: [
            KavitaChapterDTO(id: 50, minNumber: loose, sortOrder: 0, pages: 1)])
        let b = KavitaVolumeDTO(id: 6, minNumber: loose, name: "Book 9", chapters: [
            KavitaChapterDTO(id: 60, minNumber: loose, sortOrder: 0, pages: 1)])
        XCTAssertEqual(KavitaClient.chapters(from: [a, b], seriesRef: ref).map(\.id), ["60", "50"])
    }

    func testSuwayomiLocalChaptersWithoutNumbersUseNaturalNames() {
        // Local-source archives: Suwayomi couldn't read numbers (-1) and the
        // files share one source position.
        let nodes = [
            SuwayomiChapterDTO(id: 3, name: "[Team] Tale - 10.cbz", chapterNumber: -1, sourceOrder: 1),
            SuwayomiChapterDTO(id: 1, name: "[Team] Tale - 1.cbz", chapterNumber: -1, sourceOrder: 1),
            SuwayomiChapterDTO(id: 2, name: "[Team] Tale - 2.cbz", chapterNumber: -1, sourceOrder: 1),
        ]
        XCTAssertEqual(SuwayomiClient.chapters(from: nodes, seriesRef: ref).map(\.id), ["1", "2", "3"])
    }

    func testSuwayomiCJKChapterNames() {
        let nodes = [
            SuwayomiChapterDTO(id: 2, name: "第十話", chapterNumber: nil, sourceOrder: nil),
            SuwayomiChapterDTO(id: 1, name: "第二話", chapterNumber: nil, sourceOrder: nil),
            SuwayomiChapterDTO(id: 3, name: "第十一話", chapterNumber: nil, sourceOrder: nil),
        ]
        XCTAssertEqual(SuwayomiClient.chapters(from: nodes, seriesRef: ref).map(\.title), ["第二話", "第十話", "第十一話"])
    }

    func testSuwayomiNewestFirstWithOneOddNumber() {
        let nodes = [
            SuwayomiChapterDTO(id: 4, name: "Ch 4", chapterNumber: 4, sourceOrder: 0),
            SuwayomiChapterDTO(id: 3, name: "Ch 3", chapterNumber: 3, sourceOrder: 1),
            SuwayomiChapterDTO(id: 9, name: "Bonus", chapterNumber: 99, sourceOrder: 2),
            SuwayomiChapterDTO(id: 2, name: "Ch 2", chapterNumber: 2, sourceOrder: 3),
            SuwayomiChapterDTO(id: 1, name: "Ch 1", chapterNumber: 1, sourceOrder: 4),
        ]
        XCTAssertEqual(SuwayomiClient.chapters(from: nodes, seriesRef: ref).map(\.id), ["1", "2", "9", "3", "4"])
    }
}
