import XCTest
@testable import MangaCore

final class BookCursorTests: XCTestCase {
    func testForwardWithinAndAcrossSections() {
        var c = BookCursor(section: 0, page: 0)
        XCTAssertEqual(c.forward(pageCounts: [0: 2], sectionCount: 3), .moved)
        XCTAssertEqual(c, BookCursor(section: 0, page: 1))
        XCTAssertEqual(c.forward(pageCounts: [0: 2], sectionCount: 3), .needsSection(1, toEnd: false))
        XCTAssertEqual(c, BookCursor(section: 0, page: 1), "doesn't move until the section is laid out")
        XCTAssertEqual(c.forward(pageCounts: [0: 2, 1: 3], sectionCount: 3), .moved)
        XCTAssertEqual(c, BookCursor(section: 1, page: 0))
    }

    func testForwardSkipsEmptySectionsAndStopsAtEnd() {
        var c = BookCursor(section: 0, page: 0)
        XCTAssertEqual(c.forward(pageCounts: [0: 1, 1: 0, 2: 1], sectionCount: 3), .moved)
        XCTAssertEqual(c, BookCursor(section: 2, page: 0))
        XCTAssertEqual(c.forward(pageCounts: [0: 1, 1: 0, 2: 1], sectionCount: 3), .atEnd)
        XCTAssertTrue(c.isAtEnd(pageCounts: [0: 1, 1: 0, 2: 1], sectionCount: 3))
    }

    func testBackwardOpensPreviousSectionOnLastPage() {
        var c = BookCursor(section: 2, page: 0)
        XCTAssertEqual(c.backward(pageCounts: [2: 1]), .needsSection(1, toEnd: true))
        XCTAssertEqual(c.backward(pageCounts: [1: 4, 2: 1]), .moved)
        XCTAssertEqual(c, BookCursor(section: 1, page: 3))
        c = BookCursor(section: 0, page: 0)
        XCTAssertEqual(c.backward(pageCounts: [0: 3]), .atStart)
    }

    func testFractionRoundTripsAcrossRelayout() {
        let c = BookCursor(section: 0, page: 3)
        let f = c.fraction(pageCount: 10)
        XCTAssertEqual(BookCursor.page(forFraction: f, pageCount: 10), 3)
        // Bigger text: twice the pages, same place in the text.
        XCTAssertEqual(BookCursor.page(forFraction: f, pageCount: 20), 6)
        XCTAssertEqual(BookCursor.page(forFraction: 0.99, pageCount: 1), 0)
        XCTAssertEqual(BookCursor.page(forFraction: 1.5, pageCount: 4), 3)
    }

    func testResumeUsesFractionOnlyForSameSection() {
        let ref = SeriesRef(serverID: UUID(), seriesID: "1")
        let chapter = Chapter(id: "9", seriesRef: ref, title: "Book", number: 1, pageCount: 12, lastPageRead: 4,
                              format: .epub)
        XCTAssertEqual(BookPositionStore.resume(chapter: chapter, saved: BookPosition(section: 4, fraction: 0.5), sectionCount: 12).fraction, 0.5)
        let other = BookPositionStore.resume(chapter: chapter, saved: BookPosition(section: 2, fraction: 0.5), sectionCount: 12)
        XCTAssertEqual(other.section, 4)
        XCTAssertEqual(other.fraction, 0)
        var read = chapter
        read.isRead = true
        XCTAssertEqual(BookPositionStore.resume(chapter: read, saved: nil, sectionCount: 12).section, 0)
    }

    func testPositionStoreIsPerProfileAndCapped() {
        let store = BookPositionStore(backing: InMemoryKeyValueStore())
        let ref = SeriesRef(serverID: UUID(), seriesID: "1")
        let chapter = Chapter(id: "9", seriesRef: ref, title: "Book", number: 1, pageCount: 12)
        let a = UUID(), b = UUID()
        store.setPosition(BookPosition(section: 3, fraction: 0.25), profile: a, chapter: chapter)
        XCTAssertEqual(store.position(profile: a, chapter: chapter)?.section, 3)
        XCTAssertNil(store.position(profile: b, chapter: chapter))

        let backing = InMemoryKeyValueStore()
        let capped = BookPositionStore(backing: backing)
        for i in 0..<(BookPositionStore.limit + 5) {
            let ch = Chapter(id: "\(i)", seriesRef: ref, title: "", number: 0, pageCount: 1)
            capped.setPosition(BookPosition(section: 0, fraction: 0, updatedAt: Date(timeIntervalSince1970: Double(i))),
                               profile: a, chapter: ch)
        }
        let reloaded = BookPositionStore(backing: backing)
        let newest = Chapter(id: "\(BookPositionStore.limit + 4)", seriesRef: ref, title: "", number: 0, pageCount: 1)
        let oldest = Chapter(id: "0", seriesRef: ref, title: "", number: 0, pageCount: 1)
        XCTAssertNotNil(reloaded.position(profile: a, chapter: newest))
        XCTAssertNil(reloaded.position(profile: a, chapter: oldest))
    }
}
