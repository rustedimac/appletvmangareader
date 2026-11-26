import XCTest
@testable import MangaCore

final class NaturalSortTests: XCTestCase {
    private let en = Locale(identifier: "en_US_POSIX")

    private func sorted(_ names: [String], options: NaturalSort.Options = []) -> [String] {
        names.shuffled().naturallySorted(options: options, locale: en)
    }

    func testNumbersCompareByValue() {
        XCTAssertEqual(sorted(["Chapter 10", "Chapter 2", "Chapter 1", "Chapter 100", "Chapter 9"]),
                       ["Chapter 1", "Chapter 2", "Chapter 9", "Chapter 10", "Chapter 100"])
    }

    func testPageFileNames() {
        XCTAssertEqual(sorted(["page10.jpg", "page2.jpg", "page1.jpg", "page011.jpg", "page003.png"]),
                       ["page1.jpg", "page2.jpg", "page003.png", "page10.jpg", "page011.jpg"])
    }

    func testDecimalChapters() {
        XCTAssertEqual(sorted(["Ch. 11", "Ch. 10.5", "Ch. 10", "Ch. 10.25", "Ch. 9"]),
                       ["Ch. 9", "Ch. 10", "Ch. 10.25", "Ch. 10.5", "Ch. 11"])
    }

    func testDotBeforeTextIsNotAFraction() {
        XCTAssertEqual(sorted(["v2.cbz", "v10.cbz", "v1.cbz"]), ["v1.cbz", "v2.cbz", "v10.cbz"])
    }

    func testVeryLongNumbersDontOverflow() {
        let a = "id 123456789012345678901234567890"
        let b = "id 99999999999999999999999999999"
        XCTAssertEqual(sorted([a, b]), [b, a])
    }

    func testLeadingZerosTieThenStable() {
        // Same value: the exact characters decide, every time.
        XCTAssertEqual(sorted(["Ch 1", "Ch 01", "Ch 001"]), ["Ch 001", "Ch 01", "Ch 1"])
        XCTAssertEqual(NaturalSort.compare("Ch 01", "Ch 1", locale: en), .orderedAscending)
        XCTAssertEqual(NaturalSort.compare("Ch 1", "Ch 01", locale: en), .orderedDescending)
        XCTAssertEqual(NaturalSort.compare("Ch 1", "Ch 1", locale: en), .orderedSame)
    }

    func testCaseAccentAndPunctuationInsensitive() {
        XCTAssertEqual(NaturalSort.compare("élan 2", "Elan 10", locale: en), .orderedAscending)
        XCTAssertEqual(NaturalSort.compare("Ch_2", "Ch-10", locale: en), .orderedAscending)
        XCTAssertEqual(NaturalSort.compare("vol.2", "VOL 10", locale: en), .orderedAscending)
    }

    func testNumberBeforeTextAndPrefixFirst() {
        XCTAssertEqual(sorted(["Volume Extra", "Volume 2", "Volume"]), ["Volume", "Volume 2", "Volume Extra"])
    }

    func testSquareBracketsDontBreakOrder() {
        XCTAssertEqual(sorted(["[Group] Story - 10 [Digital]", "[Group] Story - 2 [Digital]", "[Group] Story - 1"]),
                       ["[Group] Story - 1", "[Group] Story - 2 [Digital]", "[Group] Story - 10 [Digital]"])
        // Brackets that hold the number itself.
        XCTAssertEqual(sorted(["[10].jpg", "[2].jpg", "[1].jpg"]), ["[1].jpg", "[2].jpg", "[10].jpg"])
    }

    func testFileNameOptionIgnoresTagsAndExtension() {
        let names = ["[B Team] Tale v02.cbz", "[A Team] Tale v10.cbz", "(Digital) Tale v01.zip"]
        XCTAssertEqual(sorted(names, options: .fileName),
                       ["(Digital) Tale v01.zip", "[B Team] Tale v02.cbz", "[A Team] Tale v10.cbz"])
        // Tags with digits stay, and a name that is only tags is kept whole.
        XCTAssertEqual(NaturalSort.droppingTags("[Scans] Tale (2019) [Digital]").trimmingCharacters(in: .whitespaces),
                       "Tale (2019)")
        XCTAssertEqual(sorted(["[Beta]", "[Alpha]"], options: .fileName), ["[Alpha]", "[Beta]"])
        XCTAssertEqual(NaturalSort.droppingExtension("Chapter 10.5"), "Chapter 10.5")
        XCTAssertEqual(NaturalSort.droppingExtension("001.webp"), "001")
    }

    func testFullWidthDigits() {
        XCTAssertEqual(sorted(["第１０話", "第２話", "第１話"]), ["第１話", "第２話", "第１０話"])
        // Full-width and ASCII digits of the same value sort together.
        XCTAssertEqual(sorted(["話 3", "話 ２", "話 1"]), ["話 1", "話 ２", "話 3"])
    }

    func testKanjiNumerals() {
        XCTAssertEqual(sorted(["第十話", "第二話", "第一話", "第十一話", "第二十三話", "第百話"]),
                       ["第一話", "第二話", "第十話", "第十一話", "第二十三話", "第百話"])
        XCTAssertEqual(NaturalSort.kanjiNumber(Array("二〇二三")), 2023)
        XCTAssertEqual(NaturalSort.kanjiNumber(Array("千二百三十四")), 1234)
        XCTAssertEqual(NaturalSort.kanjiNumber(Array("百二")), 102)
    }

    func testCJKBracketsAndKoreanAndChinese() {
        XCTAssertEqual(sorted(["【完結】第3巻", "【完結】第12巻", "【完結】第1巻"]),
                       ["【完結】第1巻", "【完結】第3巻", "【完結】第12巻"])
        XCTAssertEqual(sorted(["제10화", "제2화", "제1화"]), ["제1화", "제2화", "제10화"])
        XCTAssertEqual(sorted(["第10章", "第9章"]), ["第9章", "第10章"])
    }

    func testCircledAndRomanNumeralsAreText() {
        XCTAssertNil(NaturalSort.decimalDigit("①"))
        XCTAssertNil(NaturalSort.decimalDigit("Ⅻ"))
        XCTAssertNil(NaturalSort.decimalDigit("½"))
        XCTAssertEqual(NaturalSort.decimalDigit("７"), 7)
        XCTAssertEqual(NaturalSort.decimalDigit("٣"), 3)
    }

    func testOrderIsTotalAndIndependentOfInput() {
        let names = ["a 1", "A 1", "a1", "a 01", "b", "B", "1", "01", "", " ", "[x]", "x"]
        let first = names.naturallySorted(locale: en)
        for _ in 0..<20 {
            XCTAssertEqual(names.shuffled().naturallySorted(locale: en), first)
        }
    }

    func testSortByKeyPath() {
        struct Item { var name: String }
        let items = [Item(name: "Part 10"), Item(name: "Part 9")]
        XCTAssertEqual(items.naturallySorted(by: \.name, locale: en).map(\.name), ["Part 9", "Part 10"])
    }

    func testWithoutLocale() {
        XCTAssertEqual(["b 10", "b 9", "a"].naturallySorted(locale: nil), ["a", "b 9", "b 10"])
    }
}

final class ChapterOrderingTests: XCTestCase {
    private struct C { var source: Int?; var number: Double?; var name: String; var id: Int }

    private func order(_ items: [C]) -> [Int] {
        ChapterOrdering.readingOrder(items, locale: Locale(identifier: "en_US_POSIX")) {
            ChapterOrdering.Item(sourceOrder: $0.source, number: $0.number, name: $0.name, id: $0.id)
        }.map(\.id)
    }

    func testSourceOrderAscending() {
        XCTAssertEqual(order([C(source: 2, number: 2, name: "Ch 2", id: 20),
                              C(source: 1, number: 1, name: "Ch 1", id: 10),
                              C(source: 3, number: 3, name: "Ch 3", id: 30)]), [10, 20, 30])
    }

    func testNewestFirstSourceIsFlipped() {
        XCTAssertEqual(order([C(source: 1, number: 3, name: "Ch 3", id: 30),
                              C(source: 2, number: 2, name: "Ch 2", id: 20),
                              C(source: 3, number: 1, name: "Ch 1", id: 10)]), [10, 20, 30])
    }

    func testOneMisnumberedChapterDoesntFlip() {
        // Last chapter numbered 0 (an extra); the rest go up.
        XCTAssertEqual(order([C(source: 1, number: 1, name: "Ch 1", id: 1),
                              C(source: 2, number: 2, name: "Ch 2", id: 2),
                              C(source: 3, number: 3, name: "Ch 3", id: 3),
                              C(source: 4, number: 0, name: "Extra", id: 4)]), [1, 2, 3, 4])
    }

    func testTiesUseNaturalNames() {
        XCTAssertEqual(order([C(source: 1, number: -1, name: "Side 10", id: 1),
                              C(source: 1, number: -1, name: "Side 2", id: 2),
                              C(source: 0, number: -1, name: "Intro", id: 3)]), [3, 2, 1])
    }

    func testMissingSourceOrderGoesLast() {
        XCTAssertEqual(order([C(source: nil, number: -1, name: "Bonus", id: 9),
                              C(source: 1, number: 1, name: "Ch 1", id: 1)]), [1, 9])
    }

    func testNoSourceOrderUsesNumbersThenNames() {
        XCTAssertEqual(order([C(source: nil, number: 10, name: "x", id: 1),
                              C(source: nil, number: 2, name: "y", id: 2)]), [2, 1])
        XCTAssertEqual(order([C(source: nil, number: -1, name: "[Team] Tale 10.cbz", id: 1),
                              C(source: nil, number: 2, name: "[Team] Tale 2.cbz", id: 2),
                              C(source: nil, number: nil, name: "[Team] Tale 1.cbz", id: 3)]), [3, 2, 1])
    }

    func testRunsDown() {
        XCTAssertFalse(ChapterOrdering.runsDown([]))
        XCTAssertFalse(ChapterOrdering.runsDown([5]))
        XCTAssertTrue(ChapterOrdering.runsDown([3, 2, 1]))
        XCTAssertFalse(ChapterOrdering.runsDown([1, 2, 3, 0]))
        XCTAssertTrue(ChapterOrdering.runsDown([3, 1, 2]))
    }
}
