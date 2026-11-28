import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Calibre's content server (`calibre-server`, or "Connect/share
/// → Start content server" in the Calibre app), through its JSON API
/// (`ajax/…`). Calibre-Web is a different program; it's read with the OPDS
/// type.
///
/// Mapping onto `MangaServer`:
/// - Each Calibre library is a category.
/// - Books in the same Calibre series are one series, its books the
///   chapters in series order. A book with no series is a series of one.
///   Grouping needs every book's series, so the client reads a library's
///   whole book list once (ids from `ajax/search`, metadata from
///   `ajax/books` in batches) and keeps it for a few minutes. That also
///   gives sorting by title, date added and date changed.
/// - A book opens from one of its formats, downloaded whole and read on
///   device (`DownloadedBook`): CBZ, then EPUB, then PDF, then TXT.
/// - The login is optional (Calibre runs without one unless "Require
///   username and password" is on), Basic or Digest (`PasswordAuth`).
/// - Calibre's reading positions belong to its own viewer, so progress
///   stays on the device, as with OPDS.
public final class CalibreClient: MangaServer, @unchecked Sendable {
    public let config: ServerConfig
    let transport: HTTPTransport
    public let categoryScope: Set<String>?
    let auth: PasswordAuth?
    let archives: LocalArchiveCache
    private let state = CalibreState()

    /// Formats the app reads, best first, and what each is.
    static let formatPreference: [(name: String, kind: ContentKind)] = [
        ("CBZ", .comicArchive), ("ZIP", .comicArchive), ("EPUB", .epub), ("KEPUB", .epub),
        ("PDF", .pdf), ("TXT", .text),
    ]
    /// Books read per `ajax/books` request.
    static let batchSize = 200
    /// The biggest library read whole; more books than this are left out
    /// (newest first).
    static let maxBooks = 20_000
    /// How long a library's book list is kept before it's read again.
    static let indexLifetime: TimeInterval = 300

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

    var http: HTTPClient { HTTPClient(baseURL: config.baseURL, transport: transport) }

    // MARK: MangaServer

    public func validate() async throws -> String {
        let libraries = try await libraryInfo()
        let count = libraries.libraryMap.count
        let books = try? await http.get("ajax/search/\(Self.segment(libraries.defaultLibrary ?? ""))",
                                        query: ["num": "0"], as: CalibreSearchDTO.self)
        let bookText = books.map { ", \($0.totalNum) book\($0.totalNum == 1 ? "" : "s") in the main one" } ?? ""
        return "Connected to Calibre (\(count) librar\(count == 1 ? "y" : "ies")\(bookText))"
    }

    public func categories() async throws -> [MangaCategory] {
        try await allLibraries().filter { categoryScope?.contains($0.id) ?? true }
    }

    func allLibraries() async throws -> [MangaCategory] {
        let info = try await libraryInfo()
        let names = info.libraryMap.sorted { a, b in
            // The default library first, then by name.
            if a.key == info.defaultLibrary { return true }
            if b.key == info.defaultLibrary { return false }
            return a.value.localizedStandardCompare(b.value) == .orderedAscending
        }
        return names.enumerated().map { MangaCategory(id: $1.key, name: $1.value, order: $0) }
    }

    func libraryInfo() async throws -> CalibreLibraryInfoDTO {
        if let cached = await state.info { return cached }
        let info: CalibreLibraryInfoDTO = try await http.get("ajax/library-info")
        await state.setInfo(info)
        return info
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: .default)
    }

    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary> {
        let groups = Self.sorted(try await index(category.id).groups, by: sort)
        let size = max(1, pageSize)
        let start = (max(1, page) - 1) * size
        guard start < groups.count else { return Paged(items: [], hasMore: false) }
        let slice = groups[start..<min(groups.count, start + size)]
        return Paged(items: slice.map(summary), hasMore: start + size < groups.count)
    }

    public func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] {
        guard feed == .newlyAdded else { return [] }
        var groups: [CalibreGroup] = []
        for library in try await categories() {
            groups += try await index(library.id).groups
        }
        return Self.sorted(groups, by: .recentlyAdded).prefix(limit).map { group in
            var s = summary(group)
            s.feedDate = group.added
            return s
        }
    }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var results: [SeriesSummary] = []
        for library in try await categories() {
            let found: CalibreSearchDTO = try await http.get("ajax/search/\(Self.segment(library.id))",
                                                             query: ["query": trimmed, "num": "200"])
            let ids = Set(found.bookIDs)
            let index = try await index(library.id)
            results += index.groups.filter { group in group.books.contains { ids.contains($0.id) } }.map(summary)
        }
        return results
    }

    public func seriesDetail(_ seriesID: String) async throws -> SeriesDetail {
        guard let id = CalibreSeriesID(seriesID) else { throw MangaError.notFound }
        guard let group = try await index(id.library).groups.first(where: { $0.id == id }) else { throw MangaError.notFound }
        let chapters = group.books.enumerated().map { index, book in
            Chapter(id: CalibreChapterID(library: id.library, book: book.id).rawValue, seriesRef: ref(seriesID),
                    title: Self.chapterTitle(book, in: group), number: Double(index + 1), pageCount: 0,
                    updatedAt: book.modified ?? book.added, format: Self.preferredFormat(book)?.kind.contentFormat)
        }
        var people = Set<String>()
        let authors = group.books.flatMap(\.authors).filter { people.insert($0).inserted }
        var seenTags = Set<String>()
        let tags = group.books.flatMap(\.tags).filter { seenTags.insert($0.lowercased()).inserted }
        var detail = SeriesDetail(summary: summary(group), synopsis: group.books.first?.comments.map(Self.plainText),
                                  authors: authors, genres: tags, status: nil, chapters: chapters)
        detail.latestChapterAt = group.added
        return detail
    }

    public func chapterCount(seriesID: String) async throws -> SeriesCount {
        guard let id = CalibreSeriesID(seriesID),
              let group = try await index(id.library).groups.first(where: { $0.id == id }) else { throw MangaError.notFound }
        return SeriesCount(count: group.books.count, unit: .book)
    }

    public func pages(for chapter: Chapter) async throws -> [PageDescriptor] {
        try await download(chapter).pages()
    }

    public func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {
        // Calibre's read positions are its viewer's; the app keeps progress.
    }

    public func markUnread(chapters: [Chapter]) async throws {}

    public func markSeriesUnread(_ seriesID: String) async throws {}

    public func authorize(_ request: URLRequest) -> URLRequest {
        guard let auth, let host = request.url?.host, host == config.baseURL.host else { return request }
        var r = request
        r.setValue(auth.header(for: r), forHTTPHeaderField: "Authorization")
        return r
    }

    // MARK: Content filters (Calibre tags count as genres)

    public func contentFacets() async throws -> ContentFacets {
        var seen = Set<String>()
        var tags: [String] = []
        for library in try await allLibraries() {
            for book in try await index(library.id).books.values {
                for tag in book.tags where seen.insert(tag.lowercased()).inserted { tags.append(tag) }
            }
        }
        return ContentFacets(genres: tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    public func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        guard filter.isActive else { return [] }
        var hidden = Set<String>()
        for library in try await allLibraries() {
            for group in try await index(library.id).groups
            where group.books.contains(where: { filter.hides(genres: $0.tags, supportsAgeRating: false) }) {
                hidden.insert(group.id.rawValue)
            }
        }
        return hidden
    }

    // MARK: Library index

    /// A library's books and series, read whole and kept for a few minutes.
    func index(_ library: String) async throws -> CalibreIndex {
        if let cached = await state.index(library, maxAge: Self.indexLifetime) { return cached }
        return try await state.loading(library) { [self] in try await loadIndex(library) }
    }

    func loadIndex(_ library: String) async throws -> CalibreIndex {
        let path = "ajax/search/\(Self.segment(library))"
        var ids: [Int] = []
        var total = Int.max
        while ids.count < min(total, Self.maxBooks) {
            let page: CalibreSearchDTO = try await http.get(path, query: [
                "num": "1000", "offset": String(ids.count), "sort": "timestamp", "sort_order": "desc",
            ])
            total = page.totalNum
            if page.bookIDs.isEmpty { break }
            ids += page.bookIDs
        }
        var books: [Int: CalibreBookDTO] = [:]
        let batches = stride(from: 0, to: ids.count, by: Self.batchSize).map { Array(ids[$0..<min(ids.count, $0 + Self.batchSize)]) }
        try await withThrowingTaskGroup(of: [Int: CalibreBookDTO].self) { group in
            var next = 0
            func add() {
                guard next < batches.count else { return }
                let batch = batches[next]
                next += 1
                group.addTask { try await self.books(batch, library: library) }
            }
            for _ in 0..<4 { add() }
            while let result = try await group.next() {
                books.merge(result) { a, _ in a }
                add()
            }
        }
        return CalibreIndex(library: library, order: ids, books: books)
    }

    func books(_ ids: [Int], library: String) async throws -> [Int: CalibreBookDTO] {
        let raw: [String: CalibreBookDTO?] = try await http.get("ajax/books/\(Self.segment(library))",
                                                               query: ["ids": ids.map(String.init).joined(separator: ",")])
        var out: [Int: CalibreBookDTO] = [:]
        for (key, value) in raw {
            guard var book = value, let id = Int(key) else { continue }
            if book.id < 0 { book.id = id }
            out[id] = book
        }
        return out
    }

    // MARK: Mapping

    func ref(_ id: String) -> SeriesRef { SeriesRef(serverID: config.id, seriesID: id) }

    func summary(_ group: CalibreGroup) -> SeriesSummary {
        let formats = Set(group.books.map { Self.preferredFormat($0)?.kind.contentFormat })
        return SeriesSummary(ref: ref(group.id.rawValue), title: group.title, coverURL: coverURL(group.books.first),
                             libraryID: group.id.library, chapterCount: group.books.count, countUnit: .book,
                             format: formats.count == 1 ? formats.first! : nil)
    }

    /// Poster-sized thumbnail, or the full cover.
    func coverURL(_ book: CalibreBookDTO?) -> URL? {
        guard let book else { return nil }
        if let thumb = book.thumbnail.flatMap(absolute),
           var components = URLComponents(url: thumb, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []).filter { $0.name != "sz" } + [URLQueryItem(name: "sz", value: "400x600")]
            if let url = components.url { return url }
        }
        return book.cover.flatMap(absolute)
    }

    /// Calibre's own links are absolute paths (they include any URL prefix
    /// the server runs under).
    func absolute(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let parts = path.split(separator: "?", maxSplits: 1).map(String.init)
        components.percentEncodedPath = parts[0].hasPrefix("/") ? parts[0] : "/" + parts[0]
        components.percentEncodedQuery = parts.count > 1 ? parts[1] : nil
        return components.url
    }

    static func preferredFormat(_ book: CalibreBookDTO) -> (name: String, kind: ContentKind)? {
        let have = Set(book.formats.map { $0.uppercased() })
        return formatPreference.first { have.contains($0.name) }
    }

    /// "Vol. 3" style titles for books in a series whose title is just the
    /// series name; otherwise the book's own title.
    static func chapterTitle(_ book: CalibreBookDTO, in group: CalibreGroup) -> String {
        guard group.isSeries, book.title.caseInsensitiveCompare(group.title) == .orderedSame,
              let index = book.seriesIndex else { return book.title }
        let number = index == index.rounded() ? String(Int(index)) : String(index)
        return "\(group.title) \(number)"
    }

    /// Calibre comments are HTML; the synopsis is plain text.
    static func plainText(_ html: String) -> String {
        let blocks = HTMLBookParser().parse(html).blocks.map(\.plainText).filter { !$0.isEmpty }
        return blocks.joined(separator: "\n\n")
    }

    func download(_ chapter: Chapter) async throws -> DownloadedBook {
        guard let id = CalibreChapterID(chapter.id) else { throw MangaError.notFound }
        let book: CalibreBookDTO
        if let known = try await index(id.library).books[id.book] {
            book = known
        } else if let fetched = try await books([id.book], library: id.library)[id.book] {
            book = fetched
        } else {
            throw MangaError.notFound
        }
        guard let format = Self.preferredFormat(book) else {
            let have = book.formats.joined(separator: ", ")
            throw MangaError.decoding(have.isEmpty ? "This book has no file to read."
                                                   : "This book's formats (\(have)) can't be read here.")
        }
        var r = URLRequest(url: try http.url("get/\(format.name)/\(id.book)/\(Self.segment(id.library))"))
        r.timeoutInterval = 300
        return DownloadedBook(request: authorize(r), kind: format.kind, archives: archives, transport: transport)
    }

    static func segment(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(["-", "_", "."])) ?? s
    }

    static func sorted(_ groups: [CalibreGroup], by sort: LibrarySort) -> [CalibreGroup] {
        func byTitle(_ a: CalibreGroup, _ b: CalibreGroup) -> Bool {
            a.sortTitle.localizedStandardCompare(b.sortTitle) == .orderedAscending
        }
        switch sort {
        case .titleAscending, .recentlyRead: return groups.sorted(by: byTitle)
        case .titleDescending: return groups.sorted { byTitle($1, $0) }
        case .recentlyAdded:
            return groups.sorted { ($0.added ?? .distantPast, $1.sortTitle) > ($1.added ?? .distantPast, $0.sortTitle) }
        case .recentlyUpdated:
            return groups.sorted { ($0.updated ?? .distantPast, $1.sortTitle) > ($1.updated ?? .distantPast, $0.sortTitle) }
        }
    }
}

extension CalibreClient: DownloadsBookFiles {
    public func bookManifest(for chapter: Chapter) async throws -> BookManifest {
        try await download(chapter).manifest(title: chapter.title)
    }

    public func bookSection(_ index: Int, of chapter: Chapter) async throws -> BookSection {
        try await download(chapter).section(index)
    }
}

// MARK: - Ids and the index

/// Series ids: `s:<library>:<series name>` or `b:<library>:<book id>`, each
/// part percent-encoded.
struct CalibreSeriesID: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case series(String), book(Int) }
    var library: String
    var kind: Kind

    init(library: String, kind: Kind) {
        self.library = library
        self.kind = kind
    }

    init?(_ raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let library = parts[1].removingPercentEncoding,
              let value = parts[2].removingPercentEncoding else { return nil }
        self.library = library
        switch parts[0] {
        case "s": kind = .series(value)
        case "b":
            guard let id = Int(value) else { return nil }
            kind = .book(id)
        default: return nil
        }
    }

    var rawValue: String {
        let lib = CalibreSeriesID.escape(library)
        switch kind {
        case .series(let name): return "s:\(lib):\(CalibreSeriesID.escape(name))"
        case .book(let id): return "b:\(lib):\(id)"
        }
    }

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union([" ", "-", "_", "."])) ?? s
    }
}

/// Chapter ids: `c:<library>:<book id>`. The format is picked when the
/// book opens, so adding a format in Calibre keeps the progress.
struct CalibreChapterID: Hashable, Sendable {
    var library: String
    var book: Int

    init(library: String, book: Int) {
        self.library = library
        self.book = book
    }

    init?(_ raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "c", let library = parts[1].removingPercentEncoding,
              let book = Int(parts[2]) else { return nil }
        self.library = library
        self.book = book
    }

    var rawValue: String { "c:\(CalibreSeriesID.escape(library)):\(book)" }
}

/// A Calibre series, or a book on its own.
struct CalibreGroup: Hashable, Sendable {
    var id: CalibreSeriesID
    var title: String
    /// In series order.
    var books: [CalibreBookDTO]
    var isSeries: Bool { if case .series = id.kind { return true } else { return false } }
    var sortTitle: String { isSeries ? title : (books.first?.titleSort ?? title) }
    var added: Date? { books.compactMap(\.added).max() }
    var updated: Date? { books.compactMap { $0.modified ?? $0.added }.max() }
}

extension CalibreBookDTO: Hashable {
    static func == (a: CalibreBookDTO, b: CalibreBookDTO) -> Bool { a.id == b.id && a.lastModified == b.lastModified }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One library's books, grouped into series.
struct CalibreIndex: Sendable {
    var library: String
    var books: [Int: CalibreBookDTO]
    var groups: [CalibreGroup]

    init(library: String, order: [Int], books: [Int: CalibreBookDTO]) {
        self.library = library
        self.books = books
        var seriesBooks: [String: [CalibreBookDTO]] = [:]
        var seriesNames: [String: String] = [:]
        var groups: [CalibreGroup] = []
        for id in order {
            guard let book = books[id] else { continue }
            if let series = book.series {
                let key = series.lowercased()
                if seriesBooks[key] == nil { seriesNames[key] = series }
                seriesBooks[key, default: []].append(book)
            } else {
                groups.append(CalibreGroup(id: CalibreSeriesID(library: library, kind: .book(book.id)), title: book.title,
                                           books: [book]))
            }
        }
        for (key, list) in seriesBooks {
            let name = seriesNames[key] ?? key
            let ordered = list.sorted { ($0.seriesIndex ?? .infinity, $0.id) < ($1.seriesIndex ?? .infinity, $1.id) }
            groups.append(CalibreGroup(id: CalibreSeriesID(library: library, kind: .series(name)), title: name, books: ordered))
        }
        self.groups = groups
    }
}

/// Per-client caches.
actor CalibreState {
    var info: CalibreLibraryInfoDTO?
    private var indexes: [String: (CalibreIndex, Date)] = [:]
    private var running: [String: Task<CalibreIndex, Error>] = [:]

    func setInfo(_ value: CalibreLibraryInfoDTO) { info = value }

    func index(_ library: String, maxAge: TimeInterval) -> CalibreIndex? {
        guard let (index, date) = indexes[library], Date().timeIntervalSince(date) < maxAge else { return nil }
        return index
    }

    /// Loads a library once even when several screens ask at the same time.
    func loading(_ library: String, _ load: @escaping @Sendable () async throws -> CalibreIndex) async throws -> CalibreIndex {
        if let task = running[library] { return try await task.value }
        let task = Task { try await load() }
        running[library] = task
        defer { running[library] = nil }
        let index = try await task.value
        indexes[library] = (index, Date())
        return index
    }
}
