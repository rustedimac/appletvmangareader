# Reading PDFs and ebooks

The app is not manga-only. Libraries also hold western comics, PDF
magazines and text ebooks (EPUB, plain text). This note records what each
backend serves for those formats, what tvOS can render, and what the app
does with it.

## What the backends serve

### Kavita (verified against Kavita's source, `Kareadita/Kavita` develop, late 2026)

Every series and chapter has a format, Kavita's `MangaFormat` enum:
`Image = 0`, `Archive = 1` (cbz/cbr/zip/rar/7z), `Unknown = 2`,
`Epub = 3`, `Pdf = 4`. `SeriesDto.format` carries it for a series and
`ChapterDto.files[].format` for each chapter (`ChapterDto.Format` is just the
first file's format). Library types (`LibraryType`) are `Manga = 0`,
`Comic = 1`, `Book = 2`, `Image = 3`, `LightNovel = 4`, `ComicVine = 5`.
EPUB and PDF can live in any library type, so the app goes by the file
format, not the library type.

**Archives and images** use `api/Reader/image?chapterId=&page=&apiKey=` (what
the manga readers already use).

**PDF.** Two ways in:

- `api/Reader/image?...&extractPdf=true` renders each PDF page to an image on
  the server, and `api/Reader/file-dimensions?chapterId=&extractPdf=true`
  gives every page's size up front. Mihon's Kavita extension reads PDFs this
  way. The app already passes `extractPdf=true` everywhere, so PDF chapters
  open in the paged and vertical readers like any archive, with double-page
  spreads, preloading and the image cache.
- `api/Reader/pdf?chapterId=&apiKey=` streams the original file (Kavita's
  web reader feeds it to pdf.js). Not used: tvOS has no PDFKit, and drawing
  pages on device costs memory and battery without looking better than the
  server-rendered pages at TV resolution.

**EPUB.** Kavita does not render EPUBs to images. Its book reader API
(`BookController`) serves the book one spine item ("page") at a time:

| Endpoint | Returns |
| --- | --- |
| `GET api/Book/{chapterId}/book-info` | `BookInfoDto`: `bookTitle`, `seriesName`, `seriesFormat`, `pages` (the spine item count), `libraryId`, `volumeId`, `seriesId`, `chapterNumber`, `chapterTitle`, `isSpecial`. |
| `GET api/Book/{chapterId}/chapters` | The table of contents: `[BookChapterItem]` with `title`, `part` (an anchor id inside the page), `page` (spine index) and nested `children`. |
| `GET api/Book/{chapterId}/book-page?page=N` | One spine item as an HTML fragment: the `<body>` content wrapped in a `<div>`, with styles scoped and inlined, links rewritten to `kavita-page`/`kavita-part` attributes, and image `src` rewritten to `//host/api/book/{chapterId}/book-resources?apiKey=…&file=…` (protocol-relative, with an image-only key). With `Accept: application/json` it comes back as a JSON string. |
| `GET api/Book/{chapterId}/book-resources?file=` | An image, font or stylesheet from inside the EPUB. |

All of these need the user's JWT (`Authorization: Bearer`), except that
resource URLs carry their own key. Progress uses the same
`POST api/Reader/progress` as images: `pageNum` is the spine index, and
`bookScrollId` (optional) is an XPath-like id Kavita's web reader uses to
return to the exact paragraph.

### Suwayomi

Suwayomi serves only images. Online sources are image chapters. The local
source reads folders, zip/cbz, rar/cbr and EPUB, but it treats an EPUB as a
container of images (the way Mihon's local source does), so text EPUBs show
up as empty or image-only chapters. There's no PDF support. Everything from
Suwayomi goes through the image readers; format labels don't apply.

### OPDS, Komga, Calibre and other sources

- **OPDS 1.2 / OPDS-PSE** (Kavita, Komga, Calibre-web, Ubooquity, Internet
  Archive): feeds list acquisition links with MIME types
  (`application/epub+zip`, `application/pdf`, `application/x-cbz`,
  `text/plain`). The page streaming extension (PSE) gives image URLs per page
  for comics, and Komga and Kavita also render PDF pages through PSE. For EPUB
  and plain text, OPDS offers only the whole file, so the app would download
  it and parse it on device (zip + OPF + XHTML), then feed the same
  `BookSection` model the Kavita path produces.
- **Komga** has its own API: `/api/v1/books/{id}/pages/{n}` renders PDF pages
  and `/api/v1/books/{id}/manifest` is a Readium WebPub manifest with
  per-resource URLs for EPUBs, so it maps directly onto `BookProviding`.
- **Internet Archive** public-domain books: IIIF gives page images for
  scanned books (image readers); many also have EPUB and plain-text
  derivatives (text reader).

## What tvOS can render

| Option | On tvOS? | Notes |
| --- | --- | --- |
| WebKit (`WKWebView`) | No | Not available on tvOS, so no HTML rendering and no pdf.js. |
| `NSAttributedString(html:)` | Avoid | Uses WebKit under the hood, main thread only, slow and unsupported in practice on tvOS. |
| PDFKit | No | iOS, macOS and visionOS only. |
| CoreGraphics `CGPDFDocument` | Yes | Can draw PDF pages into bitmaps if a source only offers the raw file. Not needed for Kavita (server-rendered pages). |
| TextKit 1 (`NSLayoutManager`, `NSTextContainer`) | Yes | Lays attributed text out into a chain of page-sized containers, which is exactly pagination. Supports image attachments, paragraph styles and hyphenation. |
| SwiftUI `Text` | Yes | Fine for short text, but has no way to report where a page ends. |

## What the app does (first version)

- **Formats in the model.** `ContentFormat` (`images`, `pdf`, `epub`,
  `text`) on `SeriesSummary` and `Chapter`. Kavita maps `MangaFormat` into
  it; Suwayomi is always `images`. Posters and chapter rows show a small
  PDF / EPUB badge, and the series detail line names the format. Image
  content (manga, comics, archives) shows no badge, so manga flows look the
  same as before.
- **PDF** goes through the existing paged and vertical readers as
  server-rendered pages. Nothing new to learn: spreads, preloading, the menu
  and progress all work.
- **EPUB and text** open in a new book reader (`Reader/Book/`):
  - `BookProviding` (MangaCore) is the backend capability: a manifest
    (title, section count, table of contents) and one section at a time.
    `KavitaClient` implements it with the book API above.
  - `HTMLBookParser` (MangaCore) turns Kavita's HTML fragment into
    `BookBlock`s (headings, paragraphs with bold/italic runs, block quotes,
    list items, preformatted text, rules and images). It's a small tolerant
    tokenizer, because the HTML isn't always well-formed XML, and it drops
    scripts, styles and Kavita's injected bookmark/annotation markup.
    `PlainTextBookParser` does the same for `.txt` (blank lines separate
    paragraphs).
  - The app builds an attributed string from the blocks with the reader's
    font, size, line spacing and theme, and TextKit splits it into
    screen-sized pages (one or two columns). Left/right turns the page and
    crosses into the next or previous section seamlessly; the next section
    is fetched ahead of time.
  - Settings (font size, serif or sans, line spacing, theme Dark / Sepia /
    Light, one or two columns) apply live and are saved per profile, like a
    Kindle, not per book.
  - Contents: the drawer's Contents tab lists the table of contents and
    jumps there.
  - Progress: the section index goes to Kavita as `pageNum`, so other
    Kavita clients pick up the right chapter; the position inside the
    section is kept locally (as a fraction of the section), so reopening a
    book lands on the same screen page even after the font size changes.

## Downloaded books (OPDS, Calibre, Komga EPUBs)

Servers that only hand out the whole file (OPDS catalogs such as
Calibre-Web, Calibre's content server, and Komga for text EPUBs) conform
to `DownloadsBookFiles`. `DownloadedBook` downloads the file once into its
own folder in `LocalArchiveCache` (Caches, trimmed oldest first) and reads
it on the device:

| File | How it reads |
| --- | --- |
| CBZ / ZIP | Unpacked to page images (as before). |
| PDF | Kept as `book.pdf`. Page sizes come from `CGPDFDocument` up front, so spreads pair; each page is drawn to a JPEG (longer side 2400 px) the first time `URLSessionTransport` reads its `p0000.jpg` URL (`LocalPDFRenderer`), then cached like any page. Password-protected PDFs say so. |
| EPUB | Unzipped. `EPUBPackage` reads `container.xml`, the OPF (title, manifest, spine) and the contents from the EPUB 3 nav document or the EPUB 2 NCX. Each spine item is a section, parsed with `HTMLBookParser` (only the `<body>`), with images as `file://` URLs inside the book. |
| Picture-only EPUB | Every section is one image (comics packed with Kindle Comic Converter and the like): `BookManifest.isImageOnly`, and `ReaderView` switches to the image readers, which get the pictures from `pages(for:)`. |
| TXT | Split into sections of about 40,000 characters at blank lines, parsed with `PlainTextBookParser`. |

The OPDS client prefers a comic archive, then EPUB, then PDF, then text
when an entry offers several (`OPDSEntry.preferredAcquisition`); Calibre
the same (`CalibreClient.formatPreference`). Komga keeps rendering PDF pages
itself; only EPUBs that aren't DiViNa-compatible are downloaded.

Progress for these books is kept on the device (none of these servers
take EPUB positions from other apps); the section index and the position
inside it are saved like Kavita books.

## Later

- Send `bookScrollId` to Kavita for paragraph-exact cross-device resume.
- Calibre: write positions back through its viewer API
  (`book-set-last-read-position`), if people want them shared with
  Calibre's own reader.
- Footnote pop-ups (`epub:type="noteref"`), and CSS beyond bold, italic and
  alignment.
- CBR/RAR and CB7 archives.
