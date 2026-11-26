import Foundation
#if canImport(Network)
import Network
#endif

/// The tiny HTTP side of "Back Up over Wi-Fi". tvOS has no Files app or
/// AirDrop, so while the backup screen is open the Apple TV serves a page
/// at `http://<tv-address>:<port>/<code>/` that any phone or computer on the
/// same network can open to download the backup or upload one to restore.
/// The code is random per session; anything else gets a 404.
public enum BackupHTTP {
    public struct Request: Equatable, Sendable {
        public var method: String
        public var path: String
        public var headers: [String: String]
        public var body: Data
    }

    public struct Response: Equatable, Sendable {
        public var status: Int
        public var contentType: String
        public var body: Data
        public var headers: [String: String] = [:]

        public init(status: Int, contentType: String, body: Data, headers: [String: String] = [:]) {
            self.status = status
            self.contentType = contentType
            self.body = body
            self.headers = headers
        }

        static func text(_ status: Int, _ text: String) -> Response {
            Response(status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
        }

        public var serialized: Data {
            let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed",
                          413: "Payload Too Large", 422: "Unprocessable Entity"][status] ?? "OK"
            var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
            head += "Connection: close\r\nCache-Control: no-store\r\n"
            for (k, v) in headers.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
            head += "\r\n"
            return Data(head.utf8) + body
        }
    }

    public static let maxBody = 8 * 1024 * 1024

    public enum ParseResult: Equatable {
        case incomplete
        case complete(Request)
        case invalid(Int)
    }

    /// Parses an HTTP/1.1 request once all of it has arrived.
    public static func parse(_ data: Data) -> ParseResult {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 64 * 1024 ? .invalid(400) : .incomplete
        }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return .invalid(400) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length <= maxBody else { return .invalid(413) }
        let body = data[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .complete(Request(method: String(parts[0]), path: String(parts[1]), headers: headers,
                                 body: Data(body.prefix(length))))
    }

    /// Routes a request for the session `code`.
    public static func route(_ request: Request, code: String,
                             export: () async -> Data,
                             restore: (Data) async -> Result<String, Error>) async -> Response {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let base = "/\(code)/"
        guard path == "/\(code)" || path.hasPrefix(base) else { return .text(404, "Not found") }
        let rest = path == "/\(code)" ? "" : String(path.dropFirst(base.count))
        switch (request.method, rest) {
        case ("GET", ""):
            return Response(status: 200, contentType: "text/html; charset=utf-8", body: Data(page(code: code).utf8))
        case ("GET", "backup.json"):
            let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
            return Response(status: 200, contentType: "application/json", body: await export(),
                            headers: ["Content-Disposition": "attachment; filename=\"manga-reader-backup-\(stamp).json\""])
        case ("POST", "restore"):
            switch await restore(request.body) {
            case .success(let message): return .text(200, message)
            case .failure(let error): return .text(422, error.localizedDescription)
            }
        case (_, "backup.json"), (_, "restore"), (_, ""):
            return .text(405, "Method not allowed")
        default:
            return .text(404, "Not found")
        }
    }

    static func page(code: String) -> String {
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Manga Reader backup</title>
        <style>
        body{font:17px -apple-system,system-ui,sans-serif;max-width:560px;margin:40px auto;padding:0 16px;color:#1d1d1f;background:#fff}
        @media (prefers-color-scheme:dark){body{color:#f5f5f7;background:#111}}
        h1{font-size:26px}h2{font-size:19px;margin-top:32px}
        a.button,button{display:inline-block;font:inherit;padding:12px 20px;border-radius:10px;border:0;background:#0a84ff;color:#fff;text-decoration:none;cursor:pointer}
        p.small{opacity:.7;font-size:15px}#result{margin-top:16px;white-space:pre-wrap}
        </style></head><body>
        <h1>Manga Reader backup</h1>
        <p>Profiles, servers (without logins), favorites, reading progress and reader settings from your Apple TV.</p>
        <h2>Back up</h2>
        <p><a class="button" href="/\(code)/backup.json" download>Download backup</a></p>
        <h2>Restore</h2>
        <p class="small">Merges into what's on the Apple TV: nothing is deleted, the furthest reading position wins, and settings take the backup's values.</p>
        <p><input type="file" id="file" accept="application/json,.json"></p>
        <p><button id="restore">Restore this backup</button></p>
        <div id="result"></div>
        <script>
        document.getElementById('restore').onclick = async () => {
          const out = document.getElementById('result');
          const f = document.getElementById('file').files[0];
          if (!f) { out.textContent = 'Choose a backup file first.'; return; }
          out.textContent = 'Restoring…';
          try {
            const r = await fetch('/\(code)/restore', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: await f.text()});
            out.textContent = (r.ok ? 'Restored: ' : 'Not restored: ') + await r.text();
          } catch (e) { out.textContent = 'The Apple TV didn\\'t answer. Keep the backup screen open and try again.'; }
        };
        </script>
        <p class="small">This page works only while the backup screen is open on the Apple TV.</p>
        </body></html>
        """
    }

    /// A random code for one backup session.
    public static func makeCode() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }
}

#if canImport(Network)
/// Serves `BackupHTTP` on the local network while it's running.
public final class BackupWebServer: @unchecked Sendable {
    public let code: String
    private let server: LocalHTTPServer

    public init(code: String = BackupHTTP.makeCode(),
                export: @escaping @Sendable () async -> Data,
                restore: @escaping @Sendable (Data) async -> Result<String, Error>) {
        self.code = code
        self.server = LocalHTTPServer { request in
            await BackupHTTP.route(request, code: code, export: { await export() }, restore: { await restore($0) })
        }
    }

    /// Starts listening and returns the port. Tries `preferredPort` first so
    /// the address stays the same between visits.
    public func start(preferredPort: UInt16 = 8790) async throws -> UInt16 {
        try await server.start(preferredPort: preferredPort)
    }

    public func stop() {
        server.stop()
    }
}

/// A minimal HTTP/1.1 server for pages the Apple TV serves to phones on the
/// same network (Wi-Fi backup, phone setup). One request per connection.
public final class LocalHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (BackupHTTP.Request) async -> BackupHTTP.Response
    let handler: Handler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LocalHTTPServer")

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Starts listening and returns the port. Tries `preferredPort` first
    /// (0 picks any free port).
    public func start(preferredPort: UInt16) async throws -> UInt16 {
        do {
            return try await listen(on: NWEndpoint.Port(rawValue: preferredPort) ?? .any)
        } catch {
            return try await listen(on: .any)
        }
    }

    private func listen(on port: NWEndpoint.Port) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    listener.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch BackupHTTP.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil { connection.cancel() } else { self.receive(connection, buffer: buffer) }
            case .invalid(let status):
                self.send(.text(status, "Bad request"), on: connection)
            case .complete(let request):
                let handler = self.handler
                Task {
                    let response = await handler(request)
                    self.send(response, on: connection)
                }
            }
        }
    }

    private func send(_ response: BackupHTTP.Response, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { _ in connection.cancel() })
    }
}
#endif

/// The device's IPv4 addresses on Wi-Fi/Ethernet, best first.
public enum LocalNetworkAddress {
    public static func ipv4() -> [String] {
        var result: [(name: String, address: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let address = String(cString: host)
            guard !address.hasPrefix("169.254.") else { continue }
            result.append((String(cString: ptr.pointee.ifa_name), address))
        }
        // en0 (Ethernet or Wi-Fi) first, then other en*, then the rest.
        return result.sorted { rank($0.name) < rank($1.name) }.map(\.address)
    }

    static func rank(_ name: String) -> Int {
        name == "en0" ? 0 : name.hasPrefix("en") ? 1 : 2
    }
}
