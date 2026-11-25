import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

/// Returns canned responses by matching a substring of "METHOD path?query"
/// (and, for GraphQL, the request body). Records every request.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Route {
        var match: (URLRequest, String) -> Bool
        var status: Int
        var body: String
    }

    private let lock = NSLock()
    private var routes: [Route] = []
    private(set) var requests: [URLRequest] = []

    func on(_ method: String, _ pathContains: String, status: Int = 200, body: String) {
        routes.append(Route(match: { req, _ in
            req.httpMethod == method && (req.url?.absoluteString.contains(pathContains) ?? false)
        }, status: status, body: body))
    }

    /// GraphQL: match on a substring of the query text.
    func onGraphQL(_ queryContains: String, status: Int = 200, body: String) {
        routes.append(Route(match: { req, bodyText in
            req.url?.path.hasSuffix("/api/graphql") == true && bodyText.contains(queryContains)
        }, status: status, body: body))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let bodyText = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        lock.lock()
        requests.append(request)
        let route = routes.first { $0.match(request, bodyText) }
        lock.unlock()
        guard let route else {
            let r = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (Data("no route for \(request.httpMethod ?? "") \(request.url!.absoluteString)".utf8), r)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: nil, headerFields: nil)!
        return (Data(route.body.utf8), response)
    }

    func lastRequest(containing s: String) -> URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last { ($0.url?.absoluteString.contains(s) ?? false) || String(decoding: $0.httpBody ?? Data(), as: UTF8.self).contains(s) }
    }
}

func jsonBody(_ request: URLRequest?) -> [String: Any] {
    guard let data = request?.httpBody,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return obj
}
