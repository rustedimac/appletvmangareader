import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A tiny in-memory Komga for UI tests (`-uiTesting -mockKomga`): it answers
/// the REST calls `KomgaClient` makes with invented content, so the real
/// client is exercised end to end without a server. Shapes match Komga
/// 1.30.2. Requests need `X-API-Key: <apiKey>`; images answer 404 so
/// posters show their placeholder.
public final class MockKomgaTransport: HTTPTransport, @unchecked Sendable {
    public static let apiKey = "uitest-komga-key"

    struct Book { var id: String; var series: String; var title: String; var pages: Int }
    struct Series { var id: String; var library: String; var title: String }

    let libraries = [("lib-manga", "Manga"), ("lib-comics", "Comics")]
    let series = [
        Series(id: "s-lantern", library: "lib-manga", title: "Lantern Courier"),
        Series(id: "s-paper", library: "lib-manga", title: "Paper Moon Post"),
        Series(id: "s-harbor", library: "lib-comics", title: "Harbor Lights"),
    ]
    let books = [
        Book(id: "b-lantern-1", series: "s-lantern", title: "The First Delivery", pages: 6),
        Book(id: "b-lantern-2", series: "s-lantern", title: "Night Market", pages: 5),
        Book(id: "b-paper-1", series: "s-paper", title: "Paper Moon Post", pages: 4),
        Book(id: "b-harbor-1", series: "s-harbor", title: "Harbor Lights", pages: 4),
    ]

    private let lock = NSLock()
    /// bookID → (one-based page, completed)
    private var progress: [String: (Int, Bool)] = [:]

    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw MangaError.invalidURL("") }
        let path = url.path
        let method = request.httpMethod ?? "GET"
        guard request.value(forHTTPHeaderField: "X-API-Key") == Self.apiKey else {
            return respond(url, 401, #"{"status":401,"error":"Unauthorized"}"#)
        }
        let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]

        switch (method, path) {
        case ("GET", "/api/v2/users/me"):
            return respond(url, 200, #"{"id":"u1","email":"reader@example.org","roles":["USER"]}"#)
        case ("GET", "/actuator/info"):
            return respond(url, 200, #"{"build":{"version":"1.30.2"}}"#)
        case ("GET", "/api/v1/libraries"):
            let list = libraries.map { #"{"id":"\#($0.0)","name":"\#($0.1)","unavailable":false}"# }
            return respond(url, 200, "[" + list.joined(separator: ",") + "]")
        case ("POST", "/api/v1/series/list"):
            let ids = Self.values(of: "libraryId", in: body["condition"])
            let text = (body["fullTextSearch"] as? String)?.lowercased()
            let found = series.filter { (ids.isEmpty || ids.contains($0.library)) && (text.map($0.title.lowercased().contains) ?? true) }
            return respond(url, 200, page(found.map(seriesJSON)))
        case ("GET", "/api/v1/series/new"), ("GET", "/api/v1/series/updated"):
            let ids = Self.queryValue("library_id", url)?.split(separator: ",").map(String.init) ?? []
            let found = series.filter { ids.isEmpty || ids.contains($0.library) }
            return respond(url, 200, page(found.map(seriesJSON)))
        case ("POST", "/api/v1/books/list"):
            if let seriesID = Self.values(of: "seriesId", in: body["condition"]).first {
                return respond(url, 200, page(books.filter { $0.series == seriesID }.map(bookJSON)))
            }
            let inProgress = books.filter { book in lock.withLock { progress[book.id].map { !$0.1 } ?? false } }
            return respond(url, 200, page(inProgress.map(bookJSON)))
        default:
            break
        }

        let parts = path.split(separator: "/").map(String.init)
        if method == "GET", parts.count == 4, parts[2] == "libraries", let lib = libraries.first(where: { $0.0 == parts[3] }) {
            return respond(url, 200, #"{"id":"\#(lib.0)","name":"\#(lib.1)","unavailable":false}"#)
        }
        if method == "GET", parts.count == 4, parts[2] == "series", let s = series.first(where: { $0.id == parts[3] }) {
            return respond(url, 200, seriesJSON(s))
        }
        if method == "DELETE", parts.count == 5, parts[2] == "series", parts[4] == "read-progress",
           let s = series.first(where: { $0.id == parts[3] }) {
            lock.withLock { for book in books where book.series == s.id { progress[book.id] = nil } }
            return respond(url, 204, "")
        }
        if parts.count >= 5, parts[2] == "books", let book = books.first(where: { $0.id == parts[3] }) {
            if method == "GET", parts.count == 5, parts[4] == "pages" {
                let pages = (1...book.pages).map { #"{"number":\#($0),"fileName":"\#($0).png","mediaType":"image/png","width":800,"height":1200}"# }
                return respond(url, 200, "[" + pages.joined(separator: ",") + "]")
            }
            if method == "DELETE", parts[4] == "read-progress" {
                lock.withLock { progress[book.id] = nil }
                return respond(url, 204, "")
            }
            if method == "PATCH", parts[4] == "read-progress" {
                let completed = body["completed"] as? Bool ?? false
                let page = body["page"] as? Int ?? book.pages
                lock.withLock { progress[book.id] = (page, completed) }
                return respond(url, 204, "")
            }
        }
        return respond(url, 404, #"{"status":404}"#)
    }

    // MARK: JSON

    func seriesJSON(_ s: Series) -> String {
        let count = books.filter { $0.series == s.id }.count
        return #"{"id":"\#(s.id)","libraryId":"\#(s.library)","name":"\#(s.title)","booksCount":\#(count),"booksUnreadCount":\#(count),"# +
            #""metadata":{"title":"\#(s.title)","summary":"Invented series for UI tests.","status":"ONGOING","genres":["adventure"]},"# +
            #""booksMetadata":{"authors":[{"name":"Aiko Example","role":"writer"}]}}"#
    }

    func bookJSON(_ b: Book) -> String {
        let library = series.first { $0.id == b.series }?.library ?? ""
        let number = (books.filter { $0.series == b.series }.firstIndex { $0.id == b.id } ?? 0) + 1
        let progressJSON: String = lock.withLock {
            guard let p = progress[b.id] else { return "null" }
            return #"{"page":\#(p.0),"completed":\#(p.1)}"#
        }
        return #"{"id":"\#(b.id)","seriesId":"\#(b.series)","seriesTitle":"\#(series.first { $0.id == b.series }?.title ?? "")","# +
            #""libraryId":"\#(library)","name":"\#(b.title)","number":\#(number),"# +
            #""media":{"status":"READY","mediaType":"application/zip","pagesCount":\#(b.pages),"mediaProfile":"DIVINA"},"# +
            #""metadata":{"title":"\#(b.title)","number":"\#(number)","numberSort":\#(number)},"readProgress":\#(progressJSON)}"#
    }

    func page(_ items: [String]) -> String {
        #"{"content":[\#(items.joined(separator: ","))],"last":true,"number":0,"totalElements":\#(items.count)}"#
    }

    func respond(_ url: URL, _ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        let headers = ["Content-Type": "application/json"]
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    /// Every `{"<field>": {"value": …}}` inside a Komga search condition.
    static func values(of field: String, in condition: Any?) -> [String] {
        if let dict = condition as? [String: Any] {
            var found: [String] = []
            for (key, value) in dict {
                if key == field, let op = value as? [String: Any], let v = op["value"] as? String {
                    found.append(v)
                } else {
                    found += values(of: field, in: value)
                }
            }
            return found
        }
        if let list = condition as? [Any] { return list.flatMap { values(of: field, in: $0) } }
        return []
    }

    static func queryValue(_ name: String, _ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
