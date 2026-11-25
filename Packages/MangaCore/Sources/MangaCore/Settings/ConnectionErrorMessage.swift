import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Turns a failed Test Connection into a sentence that says what to fix:
/// the address (nothing answered, or something that isn't this kind of
/// server) or the login (the server answered and said no).
public enum ConnectionErrorMessage {
    public static func describe(_ error: Error, kind: ServerKind, url: URL?) -> String {
        let name = kind.displayName
        let host = url.map { u in u.host.map { h in u.port.map { "\(h):\($0)" } ?? h } ?? u.absoluteString } ?? "that address"
        let example = exampleAddress(kind)

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Couldn't find a server called \(host). Check the address for typos, for example \(example)."
            case .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .secureConnectionFailed, .cannotLoadFromNetwork:
                return "Couldn't reach \(name) at \(host). Check the address and port (for example \(example)) and that the server is running."
            case .badServerResponse, .cannotParseResponse, .badURL, .unsupportedURL:
                return notThisServer(name, host: host, example: example)
            default:
                return "Couldn't reach \(name) at \(host): \(urlError.localizedDescription)"
            }
        }

        if let mangaError = error as? MangaError {
            switch mangaError {
            case .unauthorized:
                return loginRejected(kind)
            case .missingCredential:
                return kind == .kavita ? "Enter the API key." : "Enter the login for this server."
            case .notFound, .decoding:
                return notThisServer(name, host: host, example: example)
            case .http(let status, _):
                switch status {
                case 401, 403: return loginRejected(kind)
                case 404, 405, 400: return notThisServer(name, host: host, example: example)
                case 500...599: return "\(name) at \(host) had a problem (HTTP \(status)). Try again, or check the server's logs."
                default: return notThisServer(name, host: host, example: example)
                }
            case .invalidURL:
                return "That doesn't look like a web address. Try something like \(example)."
            case .graphQL:
                return mangaError.errorDescription ?? notThisServer(name, host: host, example: example)
            }
        }

        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func loginRejected(_ kind: ServerKind) -> String {
        switch kind {
        case .kavita:
            return "Kavita rejected the API key. Copy it again from Kavita → User Settings → 3rd Party Clients: it's the last part of the OPDS URL, after /api/opds/."
        case .komga:
            return "Komga rejected the login. Check the API key, or the email and password."
        case .suwayomi, .opds:
            return "The server rejected the username or password."
        case .freeLibrary:
            return "The server rejected the login."
        }
    }

    static func notThisServer(_ name: String, host: String, example: String) -> String {
        "Something answered at \(host), but it doesn't look like \(name). Use the address you open \(name) at in a browser, for example \(example)."
    }

    static func exampleAddress(_ kind: ServerKind) -> String {
        switch kind {
        case .kavita: return "http://kavita.local:5000"
        case .komga: return "http://komga.local:25600"
        case .suwayomi: return "http://suwayomi.local:4567"
        case .opds: return "http://books.local:8083/opds"
        case .freeLibrary: return ""
        }
    }
}
