import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A tiny in-memory OPDS 1.2 catalog for UI tests (`-uiTesting -mockOPDS`),
/// in the shape Komga and Stump serve: a root with "Latest series" (folders)
/// and "All books" (books with OPDS-PSE page streaming). Invented content;
/// no login. Images answer 404 so posters show their placeholder.
public final class MockOPDSTransport: HTTPTransport, @unchecked Sendable {
    public init() {}

    static let navType = "application/atom+xml;profile=opds-catalog;kind=navigation"
    static let acqType = "application/atom+xml;profile=opds-catalog;kind=acquisition"

    struct Book { var id: String; var title: String; var pages: Int }
    let series: [(id: String, title: String, books: [Book])] = [
        ("lantern", "Lantern Courier", [Book(id: "lc1", title: "Lantern Courier 1", pages: 6),
                                        Book(id: "lc2", title: "Lantern Courier 2", pages: 5)]),
        ("paper", "Paper Moon Post", [Book(id: "pm1", title: "Paper Moon Post 1", pages: 4)]),
    ]

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw MangaError.invalidURL("") }
        let path = url.path
        switch path {
        case "/opds/v1.2/catalog":
            return atom(url, feed("root", "Test Catalog", [
                nav("latest", "Latest series", "/opds/v1.2/series/latest"),
                nav("books", "All books", "/opds/v1.2/books"),
            ], extra: #"<link rel="search" type="application/opensearchdescription+xml" href="/opds/v1.2/search"/>"#))
        case "/opds/v1.2/series/latest":
            return atom(url, feed("latest", "Latest series", series.map { nav($0.id, $0.title, "/opds/v1.2/series/\($0.id)") }))
        case "/opds/v1.2/books", "/opds/v1.2/search/feed":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value?.lowercased()
            let books = series.flatMap(\.books).filter { query == nil || $0.title.lowercased().contains(query!) }
            return atom(url, feed("books", "All books", books.map(bookEntry)))
        case "/opds/v1.2/search":
            let xml = #"<?xml version="1.0"?><OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">"# +
                #"<Url type="\#(Self.acqType)" template="/opds/v1.2/search/feed?q={searchTerms}"/></OpenSearchDescription>"#
            return respond(url, 200, xml)
        default:
            if path.hasPrefix("/opds/v1.2/series/"), let s = series.first(where: { path.hasSuffix("/" + $0.id) }) {
                return atom(url, feed(s.id, s.title, s.books.map(bookEntry)))
            }
            return respond(url, 404, "<html>not found</html>")
        }
    }

    func nav(_ id: String, _ title: String, _ href: String) -> String {
        #"<entry><title>\#(title)</title><id>\#(id)</id><link rel="subsection" type="\#(Self.navType)" href="\#(href)"/></entry>"#
    }

    func bookEntry(_ b: Book) -> String {
        #"<entry><title>\#(b.title)</title><id>\#(b.id)</id><author><name>Aiko Example</name></author>"# +
            #"<link rel="http://opds-spec.org/image/thumbnail" type="image/png" href="/opds/v1.2/books/\#(b.id)/thumbnail"/>"# +
            #"<link rel="http://opds-spec.org/acquisition" type="application/zip" href="/opds/v1.2/books/\#(b.id)/file"/>"# +
            #"<link xmlns:pse="http://vaemendis.net/opds-pse/ns" rel="http://vaemendis.net/opds-pse/stream" type="image/png" "# +
            #"href="/opds/v1.2/books/\#(b.id)/pages/{pageNumber}" pse:count="\#(b.pages)"/></entry>"#
    }

    func feed(_ id: String, _ title: String, _ entries: [String], extra: String = "") -> String {
        #"<?xml version="1.0" encoding="UTF-8"?><feed xmlns="http://www.w3.org/2005/Atom"><id>\#(id)</id><title>\#(title)</title>"# +
            extra + entries.joined() + "</feed>"
    }

    func atom(_ url: URL, _ body: String) -> (Data, HTTPURLResponse) {
        respond(url, 200, body, type: "application/atom+xml;charset=UTF-8")
    }

    func respond(_ url: URL, _ status: Int, _ body: String, type: String = "application/xml") -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type])!)
    }
}
