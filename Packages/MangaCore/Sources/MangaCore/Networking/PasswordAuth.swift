import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A username and password for servers that use HTTP Basic or Digest
/// authentication (OPDS catalogs, Calibre's content server).
///
/// Requests start with Basic. When the server answers 401 with a Digest
/// challenge (Calibre does over plain HTTP), the challenge is kept and every
/// later request, including image requests made outside the client's
/// transport, gets a Digest header for it. A stale nonce is picked up from
/// the next 401 the same way.
public final class PasswordAuth: @unchecked Sendable {
    public let username: String
    let password: String
    private let lock = NSLock()
    private var challenge: DigestChallenge?
    private var nonceCount = 0

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// Whether a Digest challenge has been seen.
    public var usesDigest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return challenge != nil
    }

    /// The Authorization header value for `request`.
    public func header(for request: URLRequest) -> String {
        lock.lock()
        guard let challenge else {
            lock.unlock()
            return "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
        }
        nonceCount += 1
        let count = nonceCount
        lock.unlock()
        return challenge.authorization(username: username, password: password,
                                       method: request.httpMethod ?? "GET", uri: Self.digestURI(request.url),
                                       nonceCount: count, cnonce: Self.makeCNonce())
    }

    /// Reads a 401's challenge. True when it's a Digest challenge worth
    /// retrying with: the first one, a new nonce, or a stale one. False
    /// when the same challenge comes back (the password is wrong).
    func learn(from response: HTTPURLResponse) -> Bool {
        guard response.statusCode == 401,
              let header = response.value(forHTTPHeaderField: "WWW-Authenticate"),
              let parsed = DigestChallenge(header: header) else { return false }
        lock.lock()
        defer { lock.unlock() }
        let isNew = challenge == nil || challenge?.nonce != parsed.nonce || parsed.stale
        guard isNew else { return false }
        challenge = parsed
        nonceCount = 0
        return true
    }

    /// The request-target the Digest response covers: path and query, as
    /// they go over the wire.
    static func digestURI(_ url: URL?) -> String {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "/" }
        var uri = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery { uri += "?" + query }
        return uri
    }

    static func makeCNonce() -> String {
        (0..<4).map { _ in String(format: "%08x", UInt32.random(in: .min ... .max)) }.joined()
    }
}

/// A parsed `WWW-Authenticate: Digest …` challenge (RFC 7616, MD5 and
/// MD5-sess; qop "auth" or none).
struct DigestChallenge: Equatable, Sendable {
    var realm: String
    var nonce: String
    var opaque: String?
    var algorithm: String
    var qop: String?
    var stale: Bool

    init?(header: String) {
        // Several challenges can share one header ("Basic …, Digest …").
        guard let range = header.range(of: "digest ", options: .caseInsensitive) else { return nil }
        let params = Self.parameters(String(header[range.upperBound...]))
        guard let nonce = params["nonce"] else { return nil }
        let algorithm = params["algorithm"] ?? "MD5"
        guard ["md5", "md5-sess"].contains(algorithm.lowercased()) else { return nil }
        realm = params["realm"] ?? ""
        self.nonce = nonce
        opaque = params["opaque"]
        self.algorithm = algorithm
        // "auth,auth-int": only auth is supported.
        let offered = params["qop"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        qop = offered.map { $0.contains("auth") ? "auth" : nil } ?? nil
        if offered != nil, qop == nil { return nil }
        stale = params["stale"]?.lowercased() == "true"
    }

    func authorization(username: String, password: String, method: String, uri: String,
                       nonceCount: Int, cnonce: String) -> String {
        let nc = String(format: "%08x", nonceCount)
        var ha1 = MD5.hex("\(username):\(realm):\(password)")
        if algorithm.lowercased() == "md5-sess" { ha1 = MD5.hex("\(ha1):\(nonce):\(cnonce)") }
        let ha2 = MD5.hex("\(method):\(uri)")
        let response = qop == nil
            ? MD5.hex("\(ha1):\(nonce):\(ha2)")
            : MD5.hex("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
        var parts = [
            "username=\(Self.quote(username))",
            "realm=\(Self.quote(realm))",
            "nonce=\(Self.quote(nonce))",
            "uri=\(Self.quote(uri))",
            "algorithm=\(algorithm)",
            "response=\(Self.quote(response))",
        ]
        if qop != nil { parts += ["qop=auth", "nc=\(nc)", "cnonce=\(Self.quote(cnonce))"] }
        if let opaque { parts.append("opaque=\(Self.quote(opaque))") }
        return "Digest " + parts.joined(separator: ", ")
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// `key=value, key="quoted, value"` pairs, keys lowercased. Stops at
    /// the next scheme name when one follows.
    static func parameters(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        let chars = Array(s)
        var i = 0
        func skipSpaces() { while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\t" { i += 1 } }
        while i < chars.count {
            skipSpaces()
            var key = ""
            while i < chars.count, chars[i] != "=", chars[i] != ",", chars[i] != " " { key.append(chars[i]); i += 1 }
            guard i < chars.count, chars[i] == "=" else {
                // A bare token: the next challenge's scheme.
                if !key.isEmpty, !result.isEmpty { break }
                continue
            }
            i += 1
            var value = ""
            if i < chars.count, chars[i] == "\"" {
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count { i += 1 }
                    value.append(chars[i])
                    i += 1
                }
                i += 1
            } else {
                while i < chars.count, chars[i] != "," { value.append(chars[i]); i += 1 }
                value = value.trimmingCharacters(in: .whitespaces)
            }
            result[key.lowercased()] = value
        }
        return result
    }
}

/// Adds `PasswordAuth` to requests for one host and retries once when a
/// 401 brings a Digest challenge.
struct PasswordAuthTransport: HTTPTransport {
    let inner: HTTPTransport
    let auth: PasswordAuth
    /// Only requests to this host get the login (never a CDN or another
    /// site a catalog links to).
    let host: String?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, !url.isFileURL, url.host == host else { return try await inner.send(request) }
        var r = request
        let wasDigest = auth.usesDigest
        r.setValue(auth.header(for: r), forHTTPHeaderField: "Authorization")
        var (data, response) = try await inner.send(r)
        if !wasDigest, response.statusCode == 400 {
            // Calibre in Digest mode answers a Basic header with 400
            // ("Unsupported authentication method"); ask without one to
            // get its challenge.
            var bare = request
            bare.setValue(nil, forHTTPHeaderField: "Authorization")
            (data, response) = try await inner.send(bare)
            guard response.statusCode == 401 else { return (data, response) }
        }
        guard response.statusCode == 401, auth.learn(from: response) else { return (data, response) }
        r.setValue(auth.header(for: r), forHTTPHeaderField: "Authorization")
        return try await inner.send(r)
    }
}
