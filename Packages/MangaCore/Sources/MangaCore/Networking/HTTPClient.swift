import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MangaError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case http(status: Int, body: String)
    case unauthorized
    case decoding(String)
    case graphQL([String])
    case missingCredential
    case notFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .http(let status, let body):
            let snippet = body.prefix(200)
            return "Server returned HTTP \(status). \(snippet)"
        case .unauthorized: return "The server rejected the login. Check the API key or password."
        case .decoding(let s): return "Unexpected response from the server: \(s)"
        case .graphQL(let messages): return messages.joined(separator: "\n")
        case .missingCredential: return "This server needs a login for the current profile."
        case .notFound: return "Not found."
        }
    }
}

/// Abstracts the network so clients can be unit-tested with canned responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Pages unpacked from a downloaded archive (`LocalArchiveCache`).
        if let url = request.url, url.isFileURL {
            guard let data = FileManager.default.contents(atPath: url.path) else {
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MangaError.http(status: -1, body: "Not an HTTP response")
        }
        return (data, http)
    }
}

/// Small JSON-over-HTTP helper shared by the Kavita and Suwayomi clients.
public struct HTTPClient: Sendable {
    public let baseURL: URL
    public let transport: HTTPTransport
    /// Headers added to every request (auth, etc).
    public var defaultHeaders: [String: String]

    public init(baseURL: URL, transport: HTTPTransport, defaultHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.transport = transport
        self.defaultHeaders = defaultHeaders
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                // Suwayomi uses epoch seconds or millis as strings/numbers.
                return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
            }
            let string = try container.decode(String.self)
            if let date = DateParsing.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(string)")
        }
        return d
    }()

    public static let encoder: JSONEncoder = JSONEncoder()

    /// Builds a URL from a path relative to the base URL (keeps any base path
    /// such as a reverse-proxy prefix) and query items.
    public func url(_ path: String, query: [String: String?] = [:]) throws -> URL {
        var trimmedBase = baseURL.absoluteString
        while trimmedBase.hasSuffix("/") { trimmedBase.removeLast() }
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(string: trimmedBase + "/" + trimmedPath) else {
            throw MangaError.invalidURL(path)
        }
        // Encode strictly (URLComponents leaves "+" and friends alone, which
        // servers then decode as a space).
        let encoded = query
            .compactMap { key, value in value.map { (key, $0) } }
            .sorted { $0.0 < $1.0 }
            .map { "\(Self.escape($0.0))=\(Self.escape($0.1))" }
        if !encoded.isEmpty {
            let existing = components.percentEncodedQuery.map { [$0] } ?? []
            components.percentEncodedQuery = (existing + encoded).joined(separator: "&")
        }
        guard let url = components.url else { throw MangaError.invalidURL(path) }
        return url
    }

    static let queryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? s
    }

    public func request(_ method: String, _ path: String, query: [String: String?] = [:], body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 30
        for (key, value) in defaultHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    @discardableResult
    public func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw MangaError.unauthorized
        case 404: throw MangaError.notFound
        default: throw MangaError.http(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }

    public func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await send(try request("GET", path, query: query))
        return try Self.decode(T.self, from: data)
    }

    public func post<T: Decodable, B: Encodable>(_ path: String, query: [String: String?] = [:], body: B, as type: T.Type = T.self) async throws -> T {
        let data = try await send(try request("POST", path, query: query, body: Self.encoder.encode(body)))
        return try Self.decode(T.self, from: data)
    }

    public func postIgnoringResponse<B: Encodable>(_ path: String, query: [String: String?] = [:], body: B) async throws {
        try await send(try request("POST", path, query: query, body: Self.encoder.encode(body)))
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MangaError.decoding(String(describing: error))
        }
    }
}

enum DateParsing {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Kavita returns .NET style timestamps without a zone, often with 7
    /// fractional digits, e.g. "2024-05-01T12:34:56.1234567".
    private static let naiveFormats: [String] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
    ]

    static func parse(_ string: String) -> Date? {
        if let d = isoWithFraction.date(from: string) ?? iso.date(from: string) { return d }
        if let number = Double(string) {
            return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in naiveFormats {
            formatter.dateFormat = format
            if let d = formatter.date(from: string) { return d }
        }
        return nil
    }
}
