import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Picks which of a server's addresses to use (`ServerConfig.addresses`):
/// the first one, in the user's order, that answers. Remembers the choice
/// for a while and across launches (the "last good" address, used for
/// images until the first request of a launch has checked again).
///
/// Clients always build URLs from `ServerConfig.baseURL`; `FailoverTransport`
/// and `MangaServer.imageRequest` rewrite them to the chosen address. URLs a
/// server hands back with one of its other addresses (OPDS links, for
/// example) are rewritten the same way.
public final class ServerAddressRouter: @unchecked Sendable {
    public static let shared = ServerAddressRouter(store: UserDefaultsStore())

    static let storeKey = "mangareader.serverAddresses.lastGood"

    /// How long a checked address is trusted before the next request checks
    /// again, so a server that came back on the home network is preferred
    /// again without relaunching.
    public var recheckInterval: TimeInterval = 10 * 60
    /// How long one address gets to answer a check.
    public var probeTimeout: TimeInterval = 5

    private let lock = NSLock()
    private var store: KeyValueStore
    private var active: [UUID: (url: URL, checkedAt: Date)] = [:]
    private var lastGood: [String: String]
    private var inFlight: [UUID: Task<URL?, Never>] = [:]
    private let now: @Sendable () -> Date

    public init(store: KeyValueStore = InMemoryKeyValueStore(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
        self.lastGood = store.data(forKey: Self.storeKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// Swaps the persistent store, e.g. for in-memory state in UI tests.
    public func reset(store: KeyValueStore) {
        lock.lock(); defer { lock.unlock() }
        self.store = store
        active = [:]
        inFlight = [:]
        lastGood = store.data(forKey: Self.storeKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// The address in use right now without checking anything: the one
    /// last chosen, or the main address.
    public func currentAddress(for config: ServerConfig) -> URL {
        guard config.hasAlternateAddresses else { return config.baseURL }
        lock.lock(); defer { lock.unlock() }
        let addresses = config.addresses
        if let a = active[config.id], addresses.contains(a.url) { return a.url }
        if let saved = lastGood[config.id.uuidString].flatMap(URL.init(string:)), addresses.contains(saved) {
            return saved
        }
        return config.baseURL
    }

    /// The address to use, checking the addresses first when nothing was
    /// chosen recently. Nil when none of them answers.
    public func resolve(_ config: ServerConfig, transport: HTTPTransport) async -> URL? {
        guard config.hasAlternateAddresses else { return config.baseURL }
        let addresses = config.addresses
        enum Start { case known(URL), wait(Task<URL?, Never>) }
        let start: Start = lock.withLock {
            if let a = active[config.id], addresses.contains(a.url), now().timeIntervalSince(a.checkedAt) < recheckInterval {
                return .known(a.url)
            }
            if let running = inFlight[config.id] { return .wait(running) }
            let timeout = probeTimeout
            let task = Task { await Self.firstReachable(addresses, transport: transport, timeout: timeout) }
            inFlight[config.id] = task
            return .wait(task)
        }
        let task: Task<URL?, Never>
        switch start {
        case .known(let url): return url
        case .wait(let running): task = running
        }

        let chosen = await task.value
        lock.withLock {
            if inFlight[config.id] == task { inFlight[config.id] = nil }
            if let chosen {
                active[config.id] = (chosen, now())
                if lastGood[config.id.uuidString] != chosen.absoluteString {
                    lastGood[config.id.uuidString] = chosen.absoluteString
                    store.set(try? JSONEncoder().encode(lastGood), forKey: Self.storeKey)
                }
            } else {
                active[config.id] = nil
            }
        }
        return chosen
    }

    /// Forgets the chosen address after a request to it couldn't connect,
    /// so the next `resolve` checks again.
    public func markFailed(_ config: ServerConfig, address: URL) {
        lock.lock(); defer { lock.unlock() }
        if active[config.id]?.url == address { active[config.id] = nil }
    }

    /// Forgets everything about a server (it was edited or removed).
    public func forget(_ serverID: UUID) {
        lock.lock(); defer { lock.unlock() }
        active[serverID] = nil
        inFlight[serverID] = nil
        if lastGood.removeValue(forKey: serverID.uuidString) != nil {
            store.set(try? JSONEncoder().encode(lastGood), forKey: Self.storeKey)
        }
    }

    /// Checks every address at once and returns the first in order that
    /// answered, without waiting for slower ones that come later in the list.
    static func firstReachable(_ addresses: [URL], transport: HTTPTransport, timeout: TimeInterval) async -> URL? {
        await withTaskGroup(of: (Int, Bool).self, returning: URL?.self) { group in
            for (index, url) in addresses.enumerated() {
                group.addTask { (index, await probe(url, transport: transport, timeout: timeout)) }
            }
            var results = [Bool?](repeating: nil, count: addresses.count)
            for await (index, ok) in group {
                results[index] = ok
                // The best address still possible is the first not known to fail.
                guard let best = results.firstIndex(where: { $0 != false }) else { return nil }
                if results[best] == true {
                    group.cancelAll()
                    return addresses[best]
                }
            }
            return nil
        }
    }

    /// True when anything at all answers at `url`: any HTTP status counts,
    /// since the check carries no login and only asks "is this the way in?".
    static func probe(_ url: URL, transport: HTTPTransport, timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        do {
            _ = try await transport.send(request)
            return true
        } catch {
            return false
        }
    }

    /// `url` with any of the server's addresses at its start replaced by
    /// `target`. URLs elsewhere are left alone.
    public static func rewrite(_ url: URL, for config: ServerConfig, to target: URL) -> URL {
        guard config.hasAlternateAddresses else { return url }
        let string = url.absoluteString
        let targetString = trimmed(target.absoluteString)
        // Longest first, so "http://host/opds" wins over "http://host".
        for address in config.addresses.map({ trimmed($0.absoluteString) }).sorted(by: { $0.count > $1.count }) {
            guard string.hasPrefix(address) else { continue }
            let rest = string.dropFirst(address.count)
            guard rest.isEmpty || rest.hasPrefix("/") || rest.hasPrefix("?") else { continue }
            if address == targetString { return url }
            return URL(string: targetString + rest) ?? url
        }
        return url
    }

    /// Same, to the address in use right now.
    public func rewrite(_ url: URL, for config: ServerConfig) -> URL {
        guard config.hasAlternateAddresses else { return url }
        return Self.rewrite(url, for: config, to: currentAddress(for: config))
    }

    private static func trimmed(_ s: String) -> String {
        var s = s
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Errors that mean "nothing answered at this address", as opposed to
    /// the server answering with an error.
    public static func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotFindHost, .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .secureConnectionFailed, .cannotLoadFromNetwork, .internationalRoamingOff,
             .dataNotAllowed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .appTransportSecurityRequiresSecureConnection:
            return true
        default:
            return false
        }
    }
}

/// Sends a server's requests to whichever of its addresses answers, and
/// moves on to the next address when the current one stops answering.
/// Servers with one address pass straight through.
public struct FailoverTransport: HTTPTransport {
    public let inner: HTTPTransport
    public let config: ServerConfig
    public let router: ServerAddressRouter

    public init(inner: HTTPTransport, config: ServerConfig, router: ServerAddressRouter = .shared) {
        self.inner = inner
        self.config = config
        self.router = router
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard config.hasAlternateAddresses, let url = request.url, !url.isFileURL else {
            return try await inner.send(request)
        }
        guard let address = await router.resolve(config, transport: inner) else { throw unreachable }
        do {
            return try await inner.send(retarget(request, url: url, to: address))
        } catch let error where ServerAddressRouter.isConnectivityError(error) {
            router.markFailed(config, address: address)
            guard let next = await router.resolve(config, transport: inner), next != address else { throw unreachable }
            return try await inner.send(retarget(request, url: url, to: next))
        }
    }

    private var unreachable: MangaError {
        .unreachable(server: config.name, addresses: config.addresses.count)
    }

    private func retarget(_ request: URLRequest, url: URL, to address: URL) -> URLRequest {
        var request = request
        request.url = ServerAddressRouter.rewrite(url, for: config, to: address)
        return request
    }
}

/// Plain-language text for errors shown in the app, connection problems
/// especially ("The operation couldn't be completed (NSURLErrorDomain
/// error -1004)" means nothing to anyone on a couch).
public enum ConnectionErrorText {
    public static func message(for error: Error) -> String {
        if let urlError = error as? URLError, let text = text(for: urlError.code) { return text }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func text(for code: URLError.Code) -> String? {
        switch code {
        case .cannotFindHost, .dnsLookupFailed:
            return "That address couldn't be found. Check the spelling, or that the Apple TV is on the same network as the server."
        case .cannotConnectToHost:
            return "Nothing answered at that address. Check the port number and that the server is running."
        case .timedOut:
            return "The server took too long to answer. Check that it's running and reachable from the Apple TV."
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return "This Apple TV isn't connected to a network."
        case .networkConnectionLost:
            return "The connection to the server dropped. Try again."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "The secure (https) connection failed. Check the server's certificate, or use its http:// address on your home network."
        case .appTransportSecurityRequiresSecureConnection:
            return "This address needs https://."
        case .badURL, .unsupportedURL:
            return "That doesn't look like a web address."
        default:
            return nil
        }
    }
}
