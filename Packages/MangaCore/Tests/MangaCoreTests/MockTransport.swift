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
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var routes: [Route] = []
    private(set) var requests: [URLRequest] = []

    /// Routes are matched in the order they were added, so register the most
    /// specific match first.
    func on(_ method: String, _ pathContains: String, status: Int = 200, body: String, headers: [String: String] = [:]) {
        routes.append(Route(match: { req, _ in
            req.httpMethod == method && (req.url?.absoluteString.contains(pathContains) ?? false)
        }, status: status, body: body, headers: headers))
    }

    /// GraphQL: match when the query text contains every substring.
    func onGraphQL(all parts: [String], status: Int = 200, body: String) {
        routes.append(Route(match: { req, bodyText in
            req.url?.path.hasSuffix("/api/graphql") == true && parts.allSatisfy { bodyText.contains($0) }
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
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: nil, headerFields: route.headers)!
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

/// Loads a JSON fixture from `Tests/MangaCoreTests/Fixtures`. Fixtures are
/// modeled on real Kavita 0.9.1.4 and Suwayomi 2.4.2366 responses, with
/// invented titles.
func fixture(_ name: String) -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        fatalError("Missing fixture \(name).json")
    }
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

/// Variables of the last GraphQL request whose query contains `s`.
func graphQLVariables(_ mock: MockTransport, _ s: String) -> [String: Any] {
    jsonBody(mock.lastRequest(containing: s))["variables"] as? [String: Any] ?? [:]
}

func graphQLQuery(_ mock: MockTransport, _ s: String) -> String {
    jsonBody(mock.lastRequest(containing: s))["query"] as? String ?? ""
}
