import XCTest
@testable import MangaCore

final class BookSettingsTests: XCTestCase {
    func testFontSizeSteps() {
        var s = BookSettings(fontSize: BookSettings.fontSizes[0])
        XCTAssertFalse(s.canShrink)
        s = s.larger()
        XCTAssertEqual(s.fontSize, BookSettings.fontSizes[1])
        s = BookSettings(fontSize: 1000)
        XCTAssertFalse(s.canGrow)
        XCTAssertEqual(s.larger().fontSize, BookSettings.fontSizes.last)
        XCTAssertEqual(s.smaller().fontSize, BookSettings.fontSizes[BookSettings.fontSizes.count - 2])
    }

    func testDecodingFillsMissingAndUnknownValues() throws {
        let data = Data(#"{"fontSize":44,"theme":"neon"}"#.utf8)
        let s = try JSONDecoder().decode(BookSettings.self, from: data)
        XCTAssertEqual(s.fontSize, 44)
        XCTAssertEqual(s.theme, .dark)
        XCTAssertEqual(s.columns, BookSettings.default.columns)
    }

    func testSettingsArePerProfileAndOldStateStillDecodes() throws {
        var state = AppState.initial()
        let profile = try XCTUnwrap(state.activeProfileID)
        XCTAssertEqual(state.bookSettings(profile: profile), .default)
        state.setBookSettings(BookSettings(theme: .sepia, columns: 1), profile: profile)
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppState.self, from: encoded)
        XCTAssertEqual(decoded.bookSettings(profile: profile).theme, .sepia)
        XCTAssertEqual(decoded.bookSettings(profile: UUID()), .default)

        // ProfileData saved before book settings existed.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfileData())) as! [String: Any]
        json.removeValue(forKey: "bookSettings")
        XCTAssertNil(try JSONDecoder().decode(ProfileData.self, from: JSONSerialization.data(withJSONObject: json)).bookSettings)
    }

    func testContentFormat() {
        XCTAssertEqual(ContentFormat(kavitaFormat: 1), .images)
        XCTAssertEqual(ContentFormat(kavitaFormat: 3), .epub)
        XCTAssertEqual(ContentFormat(kavitaFormat: 4), .pdf)
        XCTAssertNil(ContentFormat(kavitaFormat: 2))
        XCTAssertNil(ContentFormat(kavitaFormat: nil))
        XCTAssertEqual(ContentFormat(fileExtensionOrMIME: "application/epub+zip"), .epub)
        XCTAssertEqual(ContentFormat(fileExtensionOrMIME: "CBZ"), .images)
        XCTAssertEqual(ContentFormat(fileExtensionOrMIME: "txt"), .text)
        XCTAssertNil(ContentFormat.images.badge)
        XCTAssertEqual(ContentFormat.pdf.badge, "PDF")
        XCTAssertTrue(ContentFormat.epub.isText)
        XCTAssertFalse(ContentFormat.pdf.isText)
    }

    func testChapterWithoutFormatStillDecodes() throws {
        let ref = SeriesRef(serverID: UUID(), seriesID: "1")
        var chapter = Chapter(id: "1", seriesRef: ref, title: "One", number: 1, pageCount: 3)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(chapter)) as! [String: Any]
        json.removeValue(forKey: "format")
        let decoded = try JSONDecoder().decode(Chapter.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.format)
        chapter.format = .epub
        XCTAssertEqual(try JSONDecoder().decode(Chapter.self, from: JSONEncoder().encode(chapter)).format, .epub)
    }
}

final class ChapterReadLabelTests: XCTestCase {
    func testBooksCountParts() {
        let ref = SeriesRef(serverID: UUID(), seriesID: "1")
        var chapter = Chapter(id: "1", seriesRef: ref, title: "Book", number: 1, pageCount: 14, lastPageRead: 4)
        XCTAssertEqual(chapter.readLabel, "Page 5 of 14")
        chapter.format = .epub
        XCTAssertEqual(chapter.readLabel, "Part 5 of 14")
        chapter.isRead = true
        XCTAssertEqual(chapter.readLabel, "Read")
    }
}
