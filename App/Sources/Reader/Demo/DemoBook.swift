import Foundation
import MangaCore

/// A small public-domain book for UI tests of the book reader: the opening
/// of Lewis Carroll's "Alice's Adventures in Wonderland" (1865) as two
/// EPUB-style chapters (volumes), the first split into three sections with
/// a table of contents. Launch with `-uiTesting -readerDemo -readerBook`.
struct DemoBookServer: MangaServer, BookProviding {
    let config = ServerConfig(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B00C")!,
                              kind: .kavita, name: "Demo Books", baseURL: URL(string: "demo://books")!)

    static let seriesRef = SeriesRef(serverID: UUID(uuidString: "00000000-0000-0000-0000-00000000B00C")!, seriesID: "alice")
    static let series = SeriesSummary(ref: seriesRef, title: "Alice's Adventures in Wonderland", coverURL: nil,
                                      format: .epub)

    static let chapters: [Chapter] = [
        Chapter(id: "alice-1", seriesRef: seriesRef, title: "Part One", number: 1, pageCount: sections.count,
                format: .epub),
        Chapter(id: "alice-2", seriesRef: seriesRef, title: "Part Two", number: 2, pageCount: 1, format: .text),
    ]

    static let sections: [String] = [
        """
        <div class="body"><h1 id="ch1">Chapter I. Down the Rabbit-Hole</h1>
        <p>Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, &ldquo;and what is the use of a book,&rdquo; thought Alice &ldquo;without pictures or conversations?&rdquo;</p>
        <p>So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.</p>
        <p>There was nothing so <i>very</i> remarkable in that; nor did Alice think it so <i>very</i> much out of the way to hear the Rabbit say to itself, &ldquo;Oh dear! Oh dear! I shall be late!&rdquo; (when she thought it over afterwards, it occurred to her that she ought to have wondered at this, but at the time it all seemed quite natural); but when the Rabbit actually <i>took a watch out of its waistcoat-pocket</i>, and looked at it, and then hurried on, Alice started to her feet, for it flashed across her mind that she had never before seen a rabbit with either a waistcoat-pocket, or a watch to take out of it, and burning with curiosity, she ran across the field after it, and fortunately was just in time to see it pop down a large rabbit-hole under the hedge.</p>
        <p>In another moment down went Alice after it, never once considering how in the world she was to get out again.</p>
        <p>The rabbit-hole went straight on like a tunnel for some way, and then dipped suddenly down, so suddenly that Alice had not a moment to think about stopping herself before she found herself falling down a very deep well.</p>
        <p>Either the well was very deep, or she fell very slowly, for she had plenty of time as she went down to look about her and to wonder what was going to happen next. First, she tried to look down and make out what she was coming to, but it was too dark to see anything; then she looked at the sides of the well, and noticed that they were filled with cupboards and book-shelves; here and there she saw maps and pictures hung upon pegs. She took down a jar from one of the shelves as she passed; it was labelled &ldquo;ORANGE MARMALADE&rdquo;, but to her great disappointment it was empty: she did not like to drop the jar for fear of killing somebody underneath, so managed to put it into one of the cupboards as she fell past it.</p>
        <p>&ldquo;Well!&rdquo; thought Alice to herself, &ldquo;after such a fall as this, I shall think nothing of tumbling down stairs! How brave they&rsquo;ll all think me at home! Why, I wouldn&rsquo;t say anything about it, even if I fell off the top of the house!&rdquo; (Which was very likely true.)</p>
        <p>Down, down, down. Would the fall <i>never</i> come to an end? &ldquo;I wonder how many miles I&rsquo;ve fallen by this time?&rdquo; she said aloud. &ldquo;I must be getting somewhere near the centre of the earth. Let me see: that would be four thousand miles down, I think&mdash;&rdquo; (for, you see, Alice had learnt several things of this sort in her lessons in the schoolroom, and though this was not a <i>very</i> good opportunity for showing off her knowledge, as there was no one to listen to her, still it was good practice to say it over) &ldquo;&mdash;yes, that&rsquo;s about the right distance&mdash;but then I wonder what Latitude or Longitude I&rsquo;ve got to?&rdquo; (Alice had no idea what Latitude was, or Longitude either, but thought they were nice grand words to say.)</p>
        <hr/>
        <p>Presently she began again. &ldquo;I wonder if I shall fall right <i>through</i> the earth! How funny it&rsquo;ll seem to come out among the people that walk with their heads downward! The Antipathies, I think&mdash;&rdquo; (she was rather glad there <i>was</i> no one listening, this time, as it didn&rsquo;t sound at all the right word) &ldquo;&mdash;but I shall have to ask them what the name of the country is, you know. Please, Ma&rsquo;am, is this New Zealand or Australia?&rdquo; (and she tried to curtsey as she spoke&mdash;fancy <i>curtseying</i> as you&rsquo;re falling through the air! Do you think you could manage it?) &ldquo;And what an ignorant little girl she&rsquo;ll think me for asking! No, it&rsquo;ll never do to ask: perhaps I shall see it written up somewhere.&rdquo;</p>
        </div>
        """,
        """
        <div class="body"><h1 id="ch2">Chapter II. The Pool of Tears</h1>
        <p>&ldquo;Curiouser and curiouser!&rdquo; cried Alice (she was so much surprised, that for the moment she quite forgot how to speak good English); &ldquo;now I&rsquo;m opening out like the largest telescope that ever was! Good-bye, feet!&rdquo; (for when she looked down at her feet, they seemed to be almost out of sight, they were getting so far off).</p>
        <p id="tears">Just then her head struck against the roof of the hall: in fact she was now more than nine feet high, and she at once took up the little golden key and hurried off to the garden door.</p>
        </div>
        """,
        """
        <div class="body"><h1 id="ch3">Chapter III. A Caucus-Race and a Long Tale</h1>
        <p>They were indeed a queer-looking party that assembled on the bank&mdash;the birds with draggled feathers, the animals with their fur clinging close to them, and all dripping wet, cross, and uncomfortable.</p>
        </div>
        """,
    ]

    static let partTwo = """
    CHAPTER IV. THE RABBIT SENDS IN A LITTLE BILL

    It was the White Rabbit, trotting slowly back again, and looking
    anxiously about as it went, as if it had lost something; and she heard
    it muttering to itself "The Duchess! The Duchess!"
    """

    func validate() async throws -> String { "Demo" }
    func categories() async throws -> [MangaCategory] { [] }
    func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        Paged(items: [], hasMore: false)
    }
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] { [] }
    func search(_ query: String) async throws -> [SeriesSummary] { [] }
    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail { throw MangaError.notFound }
    func pages(for chapter: Chapter) async throws -> [PageDescriptor] { [] }
    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}
    func authorize(_ request: URLRequest) -> URLRequest { request }

    func bookManifest(for chapter: Chapter) async throws -> BookManifest {
        if chapter.id == "alice-2" { return BookManifest(title: "Part Two", sectionCount: 1) }
        return BookManifest(title: "Alice's Adventures in Wonderland", sectionCount: Self.sections.count, toc: [
            BookTOCEntry(title: "Down the Rabbit-Hole", section: 0, anchor: "ch1"),
            BookTOCEntry(title: "The Pool of Tears", section: 1, anchor: "ch2",
                         children: [BookTOCEntry(title: "Nine Feet High", section: 1, anchor: "tears")]),
            BookTOCEntry(title: "A Caucus-Race", section: 2, anchor: "ch3"),
        ])
    }

    func bookSection(_ index: Int, of chapter: Chapter) async throws -> BookSection {
        if chapter.id == "alice-2" { return PlainTextBookParser.parse(Self.partTwo, section: 0) }
        guard Self.sections.indices.contains(index) else { throw MangaError.notFound }
        return HTMLBookParser().parse(Self.sections[index], section: index)
    }
}
