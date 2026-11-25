import XCTest
@testable import MangaCore

final class HTMLBookParserTests: XCTestCase {
    func parse(_ html: String) -> [BookBlock] {
        HTMLBookParser(resolveURL: { URL(string: $0, relativeTo: URL(string: "http://kavita.local/"))?.absoluteURL })
            .parse(html).blocks
    }

    func testParagraphsHeadingsAndWhitespace() {
        let blocks = parse("""
        <div class="body"><h1 id="ch1">Chapter  I.
          Down the Rabbit-Hole</h1>
        <p>Alice was beginning to get   very tired
        of sitting by her sister on the bank.</p>
        <p>So she was considering</p></div>
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 1, runs: [TextRun("Chapter I. Down the Rabbit-Hole")], anchor: "ch1"),
            .paragraph(runs: [TextRun("Alice was beginning to get very tired of sitting by her sister on the bank.")],
                       alignment: .natural, anchor: nil),
            .paragraph(runs: [TextRun("So she was considering")], alignment: .natural, anchor: nil),
        ])
    }

    func testInlineStylesMergeAndNest() {
        let blocks = parse("<p>It was <i>very</i> <b>remarkable <i>indeed</i></b>.</p>")
        XCTAssertEqual(blocks, [.paragraph(runs: [
            TextRun("It was "), TextRun("very", style: .italic), TextRun(" "),
            TextRun("remarkable ", style: .bold), TextRun("indeed", style: [.bold, .italic]), TextRun("."),
        ], alignment: .natural, anchor: nil)])
    }

    func testCSSAndClassStyles() {
        let blocks = parse(#"<p><span style="font-style: italic">a</span><span class="bold">b</span></p>"#)
        XCTAssertEqual(blocks, [.paragraph(runs: [TextRun("a", style: .italic), TextRun("b", style: .bold)],
                                           alignment: .natural, anchor: nil)])
    }

    func testEntities() {
        let blocks = parse("<p>&ldquo;Oh dear!&rdquo; &amp; &#8212; &#x2014; caf&eacute; AT&T &bogus;</p>")
        XCTAssertEqual(blocks.first?.plainText, "“Oh dear!” & — — café AT&T &bogus;")
    }

    func testLineBreaksAndUnclosedParagraphs() {
        let blocks = parse("<p>Twinkle, twinkle,<br/>little bat!<br>How I wonder<p>Next")
        XCTAssertEqual(blocks.map(\.plainText), ["Twinkle, twinkle,\nlittle bat!\nHow I wonder", "Next"])
    }

    func testScriptsStylesAndCommentsAreDropped() {
        let blocks = parse("""
        <style>.x { color: red } p < q</style><script>var a = "<p>no</p>";</script>
        <!-- <p>hidden</p> --><p>Shown</p>
        """)
        XCTAssertEqual(blocks.map(\.plainText), ["Shown"])
    }

    func testImagesBreakParagraphsAndResolve() {
        let blocks = parse(#"<p>Before<img src="api/book/1/book-resources?file=a.jpg" alt="Alice"/>After</p>"#)
        XCTAssertEqual(blocks, [
            .paragraph(runs: [TextRun("Before")], alignment: .natural, anchor: nil),
            .image(url: URL(string: "http://kavita.local/api/book/1/book-resources?file=a.jpg")!, alt: "Alice"),
            .paragraph(runs: [TextRun("After")], alignment: .natural, anchor: nil),
        ])
    }

    func testSVGImage() {
        let blocks = parse(#"<svg:svg><svg:image xlink:href="http://kavita.local/c.png"/><text>no</text></svg:svg>"#)
        XCTAssertEqual(blocks, [.image(url: URL(string: "http://kavita.local/c.png")!, alt: nil)])
    }

    func testListsQuotesPreAndRules() {
        let blocks = parse("""
        <ol start="3"><li>One</li><li>Two<ul><li>Inner</li></ul></li></ol>
        <blockquote><p>Quoted</p></blockquote>
        <hr/>
        <pre>  line 1
          line 2</pre>
        """)
        XCTAssertEqual(blocks, [
            .listItem(marker: "3.", depth: 1, runs: [TextRun("One")]),
            .listItem(marker: "4.", depth: 1, runs: [TextRun("Two")]),
            .listItem(marker: "•", depth: 2, runs: [TextRun("Inner")]),
            .quote(runs: [TextRun("Quoted")], anchor: nil),
            .rule,
            .preformatted("  line 1\n  line 2"),
        ])
    }

    func testAlignmentAndAnchorsOnInnerElements() {
        let blocks = parse(#"<p class="centered">* * *</p><p><a id="note1"></a>Footnote</p>"#)
        XCTAssertEqual(blocks, [
            .paragraph(runs: [TextRun("* * *")], alignment: .center, anchor: nil),
            .paragraph(runs: [TextRun("Footnote")], alignment: .natural, anchor: "note1"),
        ])
        XCTAssertEqual(BookSection(index: 0, blocks: blocks).blockIndex(forAnchor: "note1"), 1)
    }

    func testStrayLessThanAndMalformedMarkup() {
        let blocks = parse("<p>3 < 4 and <unknown-tag>kept</unknown-tag></p><p")
        XCTAssertEqual(blocks.first?.plainText, "3 < 4 and kept")
    }

    func testPlainText() {
        let section = PlainTextBookParser.parse("""
        CHAPTER I

        It was the best of times, it was the worst of times, it was the age
        of wisdom, it was the age of foolishness, it was the epoch of belief,
        it was the epoch of incredulity.

        * * *

        Short line
        Another
        """)
        XCTAssertEqual(section.blocks, [
            .paragraph(runs: [TextRun("CHAPTER I")], alignment: .natural, anchor: nil),
            .paragraph(runs: [TextRun("It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness, it was the epoch of belief, it was the epoch of incredulity.")],
                       alignment: .natural, anchor: nil),
            .rule,
            .paragraph(runs: [TextRun("Short line\nAnother")], alignment: .natural, anchor: nil),
        ])
    }
}
