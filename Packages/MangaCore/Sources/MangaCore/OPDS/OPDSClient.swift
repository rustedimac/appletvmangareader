import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A generic OPDS catalog client (OPDS 1.2 Atom and OPDS 2.0 JSON), for
/// servers without a native client here: Calibre-Web, Calibre's content
/// server, Ubooquity, Codex, Stump, and Komga/Kavita's own OPDS feeds.
///
/// Mapping onto `MangaServer`:
/// - The address may be the catalog URL or just the host; well-known
///   catalog paths are tried (`OPDSClient.catalogPaths`).
/// - Categories are the root catalog's sections. A section whose entries
///   are themselves folders of folders ("Libraries" → "Manga" → series) is
///   replaced by its children ("Libraries › Manga").
/// - In a section, a folder entry (a series, an author…) is a series whose
///   chapters are the books inside it; a book entry is a one-chapter series.
/// - Pages stream through OPDS-PSE (`{pageNumber}`, zero-based) or an OPDS 2
///   DiViNa manifest. Otherwise the file is downloaded and read on device
///   (`DownloadedBook`): CBZ and PDF as pages, EPUB and text in the book
///   reader.
/// - OPDS has no way to write progress back, so progress stays on the
///   Apple TV (`saveProgress` does nothing; the server form turns sync off).
public final class OPDSClient: MangaServer, @unchecked Sendable {
    public let config: ServerConfig
    let transport: HTTPTransport
    public let categoryScope: Set<String>?
    /// Basic, or Digest once the server asks for it (Calibre's content
    /// server does over plain HTTP).
    let auth: PasswordAuth?
    let archives: LocalArchiveCache
    private let state = OPDSState()

    /// Tried in order after the address itself, relative to it.
    public static let catalogPaths = [
        "opds/v1.2/catalog",  // Komga, Stump
        "opds",               // Calibre-Web, Ubooquity (books), Calibre content server
        "opds-comics",        // Ubooquity (comics)
        "opds/v1.2",          // Codex
        "opds/v2/catalog",    // Komga (OPDS 2)
        "opds/v2.0/catalog",  // Stump (OPDS 2)
        "opds/v2.0",          // Codex (OPDS 2)
    ]

    /// Width passed for OPDS-PSE `{maxWidth}`.
    static let pseMaxWidth = 2560
    /// How many pages of one folder are read for its chapter list.
    static let maxFeedPages = 40

    public init(config: ServerConfig, username: String?, password: String?, categoryScope: Set<String>? = nil,
                archives: LocalArchiveCache = .shared, transport: HTTPTransport) {
        self.config = config
        self.categoryScope = categoryScope
        self.archives = archives
        if let username, !username.isEmpty {
            let auth = PasswordAuth(username: username, password: password ?? "")
            self.auth = auth
            self.transport = PasswordAuthTransport(inner: transport, auth: auth, host: config.baseURL.host)
        } else {
            auth = nil
            self.transport = transport
        }
    }

    // MARK: Fetching

    func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = 30
        r.setValue("application/atom+xml, application/opds+json;q=0.9, application/json;q=0.8, */*;q=0.5",
                   forHTTPHeaderField: "Accept")
        return authorize(r)
    }

    func feed(at url: URL) async throws -> OPDSFeed {
        if let cached = await state.feed(url) { return cached }
        let (data, response) = try await transport.send(request(url))
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw MangaError.unauthorized
        case 404: throw MangaError.notFound
        default: throw MangaError.http(status: response.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let base = response.url ?? url
        let parsed = try OPDSParser.parse(data, contentType: response.value(forHTTPHeaderField: "Content-Type"), baseURL: base)
        await state.store(parsed, for: url)
        return parsed
    }

    /// The root catalog: the address itself if it's a feed, else the first
    /// well-known path that is.
    func root() async throws -> (url: URL, feed: OPDSFeed) {
        if let known = await state.root { return known }
        var candidates = [config.baseURL]
        let base = config.baseURL.absoluteString.hasSuffix("/") ? config.baseURL : config.baseURL.appendingPathComponent("")
        for path in Self.catalogPaths {
            if let url = URL(string: path, relativeTo: base)?.absoluteURL, !candidates.contains(url) { candidates.append(url) }
        }
        var firstError: Error?
        for url in candidates {
            do {
                let found = try await feed(at: url)
                await state.setRoot((url, found))
                return (url, found)
            } catch MangaError.unauthorized {
                // The catalog is here but the login is wrong; don't keep guessing.
                throw MangaError.unauthorized
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        throw MangaError.decoding("No OPDS catalog found at this address. Try the full catalog URL, e.g. http://host/opds.")
    }

    // MARK: MangaServer

    public func validate() async throws -> String {
        let (_, feed) = try await root()
        let name = feed.title.isEmpty ? "OPDS catalog" : feed.title
        let sections = feed.entries.count
        return "Connected to \(name) (\(sections) section\(sections == 1 ? "" : "s"))"
    }

    public func categories() async throws -> [MangaCategory] {
        try await allCategories().filter { categoryScope?.contains($0.id) ?? true }
    }

    /// Every section, before the profile's selection.
    func allCategories() async throws -> [MangaCategory] {
        if let cached = await state.categories { return cached }
        let (_, rootFeed) = try await root()
        let rootURL = await state.root?.url
        var sections: [(order: Int, items: [MangaCategory])] = []
        // A flat catalog (books right in the root) is one section.
        if !rootFeed.topLevel.filter(\.isPublication).isEmpty, let rootURL {
            sections.append((-1, [MangaCategory(id: rootURL.absoluteString, name: rootFeed.title.isEmpty ? "All Books" : rootFeed.title)]))
        }
        // Sections to look into: the root's folders, then OPDS 2 groups.
        var candidates: [(title: String, url: URL)] = rootFeed.topLevel
            .filter { !$0.isPublication }
            .compactMap { entry in entry.navigationURL.map { (entry.title, $0) } }
        for group in rootFeed.groups {
            if let url = group.url, url != rootURL {
                candidates.append((group.title, url))
            } else {
                // A group without its own feed: its folders are sections.
                for entry in group.entries where !entry.isPublication {
                    if let url = entry.navigationURL { candidates.append(("\(group.title) › \(entry.title)", url)) }
                }
            }
        }
        var seenURLs = Set<URL>()
        candidates = candidates.filter { $0.url != rootURL && seenURLs.insert($0.url).inserted }
        let navs = Array(candidates.prefix(40))
        try await withThrowingTaskGroup(of: (Int, [MangaCategory]).self) { group in
            for (index, entry) in navs.enumerated() {
                group.addTask { (index, await self.expand(section: entry.title, url: entry.url)) }
            }
            for try await result in group { sections.append(result) }
        }
        var seen = Set<String>()
        let flat = sections.sorted { $0.order < $1.order }.flatMap(\.items).filter { seen.insert($0.id).inserted }
        let categories = flat.enumerated().map { MangaCategory(id: $1.id, name: $1.name, order: $0) }
        await state.setCategories(categories)
        return categories
    }

    /// A root section as categories: itself, its children (when it holds
    /// folders of folders), or nothing when it's empty or unreachable.
    func expand(section title: String, url: URL) async -> [MangaCategory] {
        guard let feed = try? await feed(at: url), !feed.entries.isEmpty else { return [] }
        let itself = [MangaCategory(id: url.absoluteString, name: title)]
        if !feed.publications.isEmpty { return itself }
        let children = feed.navigationEntries
        guard let firstURL = children.first?.navigationURL,
              let first = try? await self.feed(at: firstURL) else { return itself }
        // Children that hold books are series: keep the section whole.
        if !first.publications.isEmpty || first.navigationEntries.isEmpty || children.count > 50 || feed.nextURL != nil {
            return itself
        }
        return children.compactMap { child in
            child.navigationURL.map { MangaCategory(id: $0.absoluteString, name: "\(title) › \(child.title)") }
        }
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        guard let url = try await pageURL(category: category.id, page: max(1, page)) else {
            return Paged(items: [], hasMore: false)
        }
        let feed = try await feed(at: url)
        if let next = feed.nextURL { await state.setPage(next, category: category.id, page: max(1, page) + 1) }
        return Paged(items: feed.entries.compactMap { summary($0, category: category.id) }, hasMore: feed.nextURL != nil)
    }

    /// Page `n` of a section, following `next` links from the last known page.
    func pageURL(category: String, page: Int) async throws -> URL? {
        guard let first = URL(string: category) else { throw MangaError.invalidURL(category) }
        if page == 1 { return first }
        if let known = await state.page(category: category, page: page) { return known }
        var n = 1
        var url = first
        while n < page {
            if let known = await state.page(category: category, page: n + 1) {
                url = known
            } else {
                guard let next = try await feed(at: url).nextURL else { return nil }
                await state.setPage(next, category: category, page: n + 1)
                url = next
            }
            n += 1
        }
        return url
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        let all = try await categories()
        guard let category = Self.category(for: feed, in: all) else { return [] }
        let page = try await series(in: category, page: 1, pageSize: limit)
        return Array(page.items.prefix(limit))
    }

    /// Matches home rows to sections by name ("Keep Reading", "Latest
    /// Series", "Recently Added"…). Rows pick in a fixed order and a
    /// section is used for one row only.
    static func category(for feed: HomeFeed, in categories: [MangaCategory]) -> MangaCategory? {
        let order: [(HomeFeed, [String])] = [
            (.continueReading, ["keep reading", "continue reading", "in progress", "currently reading", "on deck"]),
            (.newlyAdded, ["latest series", "recently added", "new series", "newest", "new books", "latest additions"]),
            (.recentlyUpdated, ["latest books", "recently updated", "updated", "latest chapters", "latest"]),
        ]
        var used = Set<String>()
        for (row, words) in order {
            var found: MangaCategory?
            for word in words where found == nil {
                found = categories.first { !used.contains($0.id) && !$0.name.contains("›") && $0.name.lowercased().contains(word) }
            }
            if row == feed { return found }
            if let found { used.insert(found.id) }
        }
        return nil
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, categoryScope?.isEmpty != true else { return [] }
        let (rootURL, rootFeed) = try await root()
        guard let link = rootFeed.searchLink else { return [] }
        guard let url = try await searchURL(link, query: trimmed, base: rootURL) else { return [] }
        let results = try await feed(at: url)
        return results.entries.compactMap { summary($0, category: nil) }
    }

    func searchURL(_ link: OPDSLink, query: String, base: URL) async throws -> URL? {
        let escaped = HTTPClient.escape(query)
        if link.baseType == "application/opensearchdescription+xml" {
            if let cached = await state.searchTemplate {
                return URL(string: cached.replacingOccurrences(of: "{searchTerms}", with: escaped))
            }
            let (data, response) = try await transport.send(request(link.href))
            guard (200..<300).contains(response.statusCode),
                  let template = OPDSParser.openSearchTemplate(data, baseURL: response.url ?? link.href) else { return nil }
            await state.setSearchTemplate(template)
            return URL(string: Self.fillSearch(template, escaped))
        }
        let template = link.template ?? link.href.absoluteString
        return URL(string: Self.fillSearch(template, escaped))
    }

    /// Fills `{searchTerms}`, `{?query}` (RFC 6570) and `{query}`.
    static func fillSearch(_ template: String, _ escaped: String) -> String {
        var s = template.replacingOccurrences(of: "{searchTerms}", with: escaped)
        if let range = s.range(of: "{?query}") {
            let hasQuery = s[..<range.lowerBound].contains("?")
            s.replaceSubrange(range, with: (hasQuery ? "&" : "?") + "query=" + escaped)
        }
        s = s.replacingOccurrences(of: "{query}", with: escaped)
        // Optional OpenSearch parameters ({startPage?}) are left empty.
        return s.replacingOccurrences(of: "\\{[^}]*\\?\\}", with: "", options: .regularExpression)
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        switch OPDSSeriesID(seriesID) {
        case .folder(let url):
            return try await folderDetail(url, seriesID: seriesID)
        case .book(let book):
            let chapter = Self.chapter(book, seriesRef: ref(seriesID), number: 1)
            let summary = SeriesSummary(ref: ref(seriesID), title: book.title, coverURL: book.cover.flatMap(URL.init(string:)),
                                        format: book.format)
            return SeriesDetail(summary: summary, synopsis: book.summary, authors: book.authors, genres: [], status: nil,
                                chapters: [chapter])
        case nil:
            throw MangaError.notFound
        }
    }

    func folderDetail(_ url: URL, seriesID: String) async throws -> SeriesDetail {
        var books: [OPDSEntry] = []
        var title = ""
        var next: URL? = url
        var pages = 0
        while let current = next, pages < Self.maxFeedPages {
            let page = try await feed(at: current)
            if title.isEmpty { title = page.title }
            books += page.publications
            // A folder of folders: gather the books one level down.
            if page.publications.isEmpty, pages == 0 {
                for child in page.navigationEntries.prefix(30) {
                    guard let childURL = child.navigationURL, let childFeed = try? await feed(at: childURL) else { continue }
                    books += childFeed.publications
                }
            }
            next = page.nextURL
            pages += 1
        }
        var seen = Set<String>()
        books = books.filter { seen.insert($0.id).inserted }
        let ref = ref(seriesID)
        let chapters = books.enumerated().map { index, entry in
            Self.chapter(OPDSBook(entry), seriesRef: ref, number: Double(index + 1))
        }
        var people = Set<String>()
        let authors = books.flatMap(\.authors).filter { people.insert($0).inserted }
        let synopsis = books.count == 1 ? books[0].summary : nil
        let summary = SeriesSummary(ref: ref, title: title.isEmpty ? (books.first?.title ?? "Untitled") : title,
                                    coverURL: books.first?.coverURL)
        let genres = Array(Set(books.flatMap(\.categories))).sorted()
        return SeriesDetail(summary: summary, synopsis: synopsis, authors: authors, genres: genres, status: nil,
                            chapters: chapters)
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        guard let book = OPDSBook(chapterID: chapter.id) else { throw MangaError.notFound }
        if let manifest = book.divina.flatMap(URL.init(string:)) {
            let (data, response) = try await transport.send(request(manifest))
            if (200..<300).contains(response.statusCode),
               let decoded = try? JSONDecoder().decode(DivinaManifest.self, from: data), !decoded.readingOrder.isEmpty {
                let base = response.url ?? manifest
                return decoded.readingOrder.enumerated().compactMap { index, link in
                    guard let url = OPDSParser.resolve(link.href, base) else { return nil }
                    let size = (link.width ?? 0) > 0 && (link.height ?? 0) > 0
                        ? PageSize(width: link.width!, height: link.height!) : nil
                    return PageDescriptor(index: index, url: url, size: size)
                }
            }
        }
        if let template = book.stream, let count = book.count, count > 0 {
            return (0..<count).compactMap { index in
                let filled = template
                    .replacingOccurrences(of: "{pageNumber}", with: String(index))
                    .replacingOccurrences(of: "{maxWidth}", with: String(Self.pseMaxWidth))
                return URL(string: filled).map { PageDescriptor(index: index, url: $0) }
            }
        }
        guard let download = download(book) else {
            throw MangaError.decoding("This book has no pages or file to read.")
        }
        if download.kind == .other {
            throw MangaError.decoding("This book's format (\(book.fileType ?? download.request.url?.pathExtension ?? "")) isn't supported.")
        }
        return try await download.pages()
    }

    /// The book's file, for reading on device.
    func download(_ book: OPDSBook) -> DownloadedBook? {
        guard let file = book.file.flatMap(URL.init(string:)) else { return nil }
        var r = URLRequest(url: file)
        r.timeoutInterval = 300
        return DownloadedBook(request: authorize(r), kind: ContentKind(mediaType: book.fileType ?? "", url: file),
                              archives: archives, transport: transport)
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        // OPDS is read-only; the app keeps progress on the Apple TV.
    }

    public func markUnread(chapters: [Chapter]) async throws {
        // Nothing to clear on the server; local progress is cleared by the app.
    }

    public func markSeriesUnread(_ seriesID: String) async throws {}

    public func authorize(_ request: URLRequest) -> URLRequest {
        guard let auth, let host = request.url?.host, host == config.baseURL.host else { return request }
        var r = request
        r.setValue(auth.header(for: r), forHTTPHeaderField: "Authorization")
        return r
    }

    // MARK: Mapping

    func ref(_ id: String) -> SeriesRef { SeriesRef(serverID: config.id, seriesID: id) }

    func summary(_ entry: OPDSEntry, category: String?) -> SeriesSummary? {
        let id: String
        if entry.isPublication {
            id = OPDSSeriesID.book(OPDSBook(entry)).rawValue
        } else if let url = entry.navigationURL {
            id = OPDSSeriesID.folder(url).rawValue
        } else {
            return nil
        }
        let format = entry.isPublication ? OPDSBook(entry).format : nil
        return SeriesSummary(ref: ref(id), title: entry.title, coverURL: entry.coverURL, libraryID: category, format: format)
    }

    static func chapter(_ book: OPDSBook, seriesRef: SeriesRef, number: Double) -> Chapter {
        let count = book.count ?? 0
        // pse:lastRead counts from one in Komga, the main server sending it.
        let last = max(0, min((book.lastRead ?? 0) - 1, max(count - 1, 0)))
        return Chapter(id: book.chapterID, seriesRef: seriesRef, title: book.title, number: number, pageCount: count,
                       lastPageRead: last, isRead: count > 0 && (book.lastRead ?? 0) >= count, updatedAt: book.updated,
                       format: book.format)
    }
}

/// What the app needs to open one OPDS book, carried in its ids so a
/// favorite or a progress entry still works after the catalog changes.
struct OPDSBook: Codable, Hashable {
    var title: String
    /// OPDS-PSE template.
    var stream: String?
    var count: Int?
    var lastRead: Int?
    /// OPDS 2 DiViNa manifest.
    var divina: String?
    /// Acquisition link and its type.
    var file: String?
    var fileType: String?
    var cover: String?
    var summary: String?
    var authors: [String]
    var updated: Date?

    init(_ entry: OPDSEntry) {
        title = entry.title
        let pse = entry.pseLink
        stream = pse.map { $0.template ?? $0.href.absoluteString }
        count = pse?.pseCount ?? entry.numberOfPages
        lastRead = pse?.pseLastRead
        divina = entry.divinaManifest?.absoluteString
        let acquisition = entry.preferredAcquisition
        file = acquisition?.href.absoluteString
        fileType = acquisition?.baseType
        cover = entry.coverURL?.absoluteString
        summary = entry.summary.map { String($0.prefix(600)) }
        authors = Array(entry.authors.prefix(4))
        updated = entry.updated
    }

    /// How the app reads it: nil (pages) when the server streams pages or
    /// the file is a comic archive.
    var format: ContentFormat? {
        guard stream == nil, divina == nil, let file else { return nil }
        return ContentKind(mediaType: fileType ?? "", url: URL(string: file)).contentFormat
    }

    /// The chapter id leaves out display-only fields to stay short.
    var chapterID: String {
        var lean = self
        lean.title = ""
        lean.cover = nil
        lean.summary = nil
        lean.authors = []
        lean.lastRead = nil
        lean.updated = nil
        return "c:" + Self.encode(lean)
    }

    init?(chapterID: String) {
        guard chapterID.hasPrefix("c:"), let book = Self.decode(String(chapterID.dropFirst(2))) else { return nil }
        self = book
    }

    static func encode(_ book: OPDSBook) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = (try? encoder.encode(book)) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> OPDSBook? {
        var b64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(OPDSBook.self, from: data)
    }
}

/// EPUB and text books are downloaded and read on device.
extension OPDSClient: DownloadsBookFiles {
    public func bookManifest(for chapter: Chapter) async throws -> BookManifest {
        guard let book = OPDSBook(chapterID: chapter.id), let download = download(book) else { throw MangaError.notFound }
        return try await download.manifest(title: chapter.title)
    }

    public func bookSection(_ index: Int, of chapter: Chapter) async throws -> BookSection {
        guard let book = OPDSBook(chapterID: chapter.id), let download = download(book) else { throw MangaError.notFound }
        return try await download.section(index)
    }
}

/// Series ids: `f:<feed URL>` for a folder, `b:<encoded OPDSBook>` for a
/// single book.
enum OPDSSeriesID: Equatable {
    case folder(URL)
    case book(OPDSBook)

    init?(_ raw: String) {
        if raw.hasPrefix("f:"), let url = URL(string: String(raw.dropFirst(2))) {
            self = .folder(url)
        } else if raw.hasPrefix("b:"), let book = OPDSBook.decode(String(raw.dropFirst(2))) {
            self = .book(book)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .folder(let url): return "f:" + url.absoluteString
        case .book(let book): return "b:" + OPDSBook.encode(book)
        }
    }
}

/// Per-client caches: the root, sections, page links and feeds (feeds
/// expire after a minute so new books show up).
actor OPDSState {
    var root: (url: URL, feed: OPDSFeed)?
    var categories: [MangaCategory]?
    var searchTemplate: String?
    private var pages: [String: [Int: URL]] = [:]
    private var feeds: [URL: (OPDSFeed, Date)] = [:]

    func setRoot(_ value: (url: URL, feed: OPDSFeed)) { root = value }
    func setCategories(_ value: [MangaCategory]) { categories = value }
    func setSearchTemplate(_ value: String) { searchTemplate = value }

    func page(category: String, page: Int) -> URL? { pages[category]?[page] }
    func setPage(_ url: URL, category: String, page: Int) { pages[category, default: [:]][page] = url }

    func feed(_ url: URL) -> OPDSFeed? {
        guard let (feed, date) = feeds[url], Date().timeIntervalSince(date) < 60 else { return nil }
        return feed
    }

    func store(_ feed: OPDSFeed, for url: URL) {
        if feeds.count > 200 { feeds.removeAll() }
        feeds[url] = (feed, Date())
    }
}
