import Foundation

/// "Set Up from Your Phone": typing a URL and an API key with the Siri
/// Remote is slow, so while the phone setup screen is open the Apple TV
/// serves a small form at `http://<tv-address>:<port>/<code>/`. The phone
/// scans the QR code, fills in the form, and the answer lands in the Apple
/// TV's add/edit server form, where the user checks it and saves. Nothing
/// leaves the local network and nothing is saved without the TV's Save.
///
/// The code is random per visit; any other path gets a 404.
public enum PhoneSetupHTTP {
    /// What the Apple TV's form already shows, so the phone page starts from it.
    /// Never carries a key or password.
    public struct Context: Equatable, Sendable {
        public var kind: ServerKind
        /// When editing, the type can't change.
        public var kindLocked: Bool
        public var name: String
        public var address: String
        public var alternateAddresses: [String]

        public init(kind: ServerKind, kindLocked: Bool = false, name: String = "", address: String = "",
                    alternateAddresses: [String] = []) {
            self.kind = kind
            self.kindLocked = kindLocked
            self.name = name
            self.address = address
            self.alternateAddresses = alternateAddresses
        }

        public init(draft: ServerDraft, kindLocked: Bool) {
            self.init(kind: draft.kind, kindLocked: kindLocked, name: draft.name, address: draft.address,
                      alternateAddresses: draft.alternateAddresses)
        }
    }

    /// What the phone sends back.
    public struct Submission: Codable, Equatable, Sendable {
        public var kind: String?
        public var name: String?
        public var address: String?
        public var alternateAddresses: [String]?
        public var apiKey: String?
        public var username: String?
        public var password: String?

        public init(kind: String? = nil, name: String? = nil, address: String? = nil, alternateAddresses: [String]? = nil,
                    apiKey: String? = nil, username: String? = nil, password: String? = nil) {
            self.kind = kind
            self.name = name
            self.address = address
            self.alternateAddresses = alternateAddresses
            self.apiKey = apiKey
            self.username = username
            self.password = password
        }

        /// Fills the TV's form. The type changes only when it isn't locked;
        /// a pasted Kavita OPDS URL splits into address and API key. Fields
        /// that don't belong to the type are cleared.
        public func apply(to draft: inout ServerDraft, kindLocked: Bool) {
            if !kindLocked, let raw = kind, let kind = ServerKind(rawValue: raw), ServerKind.userAddable.contains(kind) {
                draft.kind = kind
            }
            func clean(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            draft.name = clean(name)
            draft.address = clean(address)
            draft.alternateAddresses = Array((alternateAddresses ?? []).map(clean).filter { !$0.isEmpty }
                .prefix(ServerDraft.maxAlternateAddresses))
            switch draft.kind {
            case .kavita:
                // An API key (or an OPDS URL in the address) wins; otherwise
                // the app signs in with the username and password.
                draft.apiKey = clean(apiKey)
                if draft.apiKey.isEmpty, !clean(username).isEmpty {
                    draft.kavitaMethod = .password
                    draft.username = clean(username)
                    draft.password = password ?? ""
                } else {
                    draft.kavitaMethod = .apiKey
                    draft.username = ""
                    draft.password = ""
                }
            case .komga:
                draft.apiKey = clean(apiKey)
                draft.username = clean(username)
                draft.password = password ?? ""
            case .suwayomi, .opds:
                draft.apiKey = ""
                draft.username = clean(username)
                draft.password = password ?? ""
            case .freeLibrary:
                break
            }
            draft.absorbOPDS()
        }

        /// Reads a JSON body, or a plain HTML form post as a fallback.
        public static func decode(_ body: Data, contentType: String?) -> Submission? {
            if contentType?.contains("application/x-www-form-urlencoded") == true {
                var components = URLComponents()
                components.percentEncodedQuery = String(decoding: body, as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
                var fields: [String: String] = [:]
                var others: [String] = []
                for item in components.queryItems ?? [] {
                    guard let value = item.value else { continue }
                    if item.name == "alternateAddress" { others.append(value) } else { fields[item.name] = value }
                }
                return Submission(kind: fields["kind"], name: fields["name"], address: fields["address"],
                                  alternateAddresses: others, apiKey: fields["apiKey"], username: fields["username"],
                                  password: fields["password"])
            }
            return try? JSONDecoder().decode(Submission.self, from: body)
        }
    }

    /// Routes a request for the visit `code`. `submit` hands a submission
    /// to the TV and returns what to show on the phone, or why it was
    /// turned down.
    public static func route(_ request: BackupHTTP.Request, code: String, context: Context,
                             submit: (Submission) async -> Result<String, Error>) async -> BackupHTTP.Response {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let base = "/\(code)/"
        guard path == "/\(code)" || path.hasPrefix(base) else { return .text(404, "Not found") }
        let rest = path == "/\(code)" ? "" : String(path.dropFirst(base.count))
        switch (request.method, rest) {
        case ("GET", ""):
            return BackupHTTP.Response(status: 200, contentType: "text/html; charset=utf-8",
                                       body: Data(page(code: code, context: context).utf8))
        case ("POST", "submit"):
            guard let submission = Submission.decode(request.body, contentType: request.headers["content-type"]),
                  !(submission.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .text(400, "Enter the server address.")
            }
            switch await submit(submission) {
            case .success(let message): return .text(200, message)
            case .failure(let error): return .text(422, error.localizedDescription)
            }
        case (_, "submit"), (_, ""):
            return .text(405, "Method not allowed")
        default:
            return .text(404, "Not found")
        }
    }

    /// Escapes text for an HTML attribute or element.
    static func html(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func page(code: String, context: Context) -> String {
        let kinds = ServerKind.userAddable.map { kind in
            let selected = kind == context.kind ? " selected" : ""
            return "<option value=\"\(kind.rawValue)\"\(selected)>\(html(kind.displayName))</option>"
        }.joined()
        let disabled = context.kindLocked ? " disabled" : ""
        let others = (context.alternateAddresses + [""]).prefix(ServerDraft.maxAlternateAddresses).map {
            "<input name=\"alternateAddress\" class=\"alt\" type=\"url\" inputmode=\"url\" autocapitalize=\"off\" autocorrect=\"off\" spellcheck=\"false\" placeholder=\"https://manga.example.com\" value=\"\(html($0))\">"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Manga Reader server setup</title>
        <style>
        body{font:17px -apple-system,system-ui,sans-serif;max-width:560px;margin:32px auto;padding:0 16px;color:#1d1d1f;background:#fff}
        @media (prefers-color-scheme:dark){body{color:#f5f5f7;background:#111}input,select{color:#f5f5f7;background:#222;border-color:#444}}
        h1{font-size:26px}label{display:block;margin-top:18px;font-weight:600}
        input,select{display:block;box-sizing:border-box;width:100%;font:inherit;padding:10px 12px;margin-top:6px;border:1px solid #c7c7cc;border-radius:10px}
        .alt{margin-top:8px}button{margin-top:24px;font:inherit;padding:12px 20px;border-radius:10px;border:0;background:#0a84ff;color:#fff;cursor:pointer}
        p.small{opacity:.7;font-size:15px}#result{margin-top:16px;white-space:pre-wrap}.hidden{display:none}
        </style></head><body>
        <h1>Add a server to Manga Reader</h1>
        <p>Fill this in and press Send. It appears in the form on the Apple TV, where you check it and save.</p>
        <form id="f">
        <label for="kind">Type</label>
        <select id="kind" name="kind"\(disabled)>\(kinds)</select>
        <label for="name">Name (optional)</label>
        <input id="name" name="name" autocapitalize="words" value="\(html(context.name))">
        <label for="address">Address</label>
        <input id="address" name="address" type="url" inputmode="url" autocapitalize="off" autocorrect="off" spellcheck="false" placeholder="http://192.168.1.10:5000" value="\(html(context.address))" required>
        <p class="small" data-for="kavita">For Kavita you can paste the OPDS URL from User Settings → 3rd Party Clients; it carries the API key.</p>
        <label>Other addresses (optional)</label>
        <p class="small">Used when the first address doesn't answer, e.g. a remote address for when you're away. Tried in order.</p>
        \(others)
        <div data-for="kavita komga"><label for="apiKey">API key</label>
        <p class="small" data-for="kavita">Or leave it empty and use your Kavita username and password below.</p>
        <input id="apiKey" name="apiKey" autocapitalize="off" autocorrect="off" spellcheck="false"></div>
        <div data-for="kavita komga suwayomi opds"><label for="username" id="userLabel">Username</label>
        <input id="username" name="username" autocapitalize="off" autocorrect="off" spellcheck="false" autocomplete="username">
        <label for="password">Password</label>
        <input id="password" name="password" type="password" autocomplete="current-password"></div>
        <button type="submit">Send to Apple TV</button>
        </form>
        <div id="result" role="status"></div>
        <p class="small">This page works only while the setup screen is open on the Apple TV. Nothing is sent outside your network.</p>
        <script>
        const kind = document.getElementById('kind');
        function show() {
          for (const el of document.querySelectorAll('[data-for]')) {
            el.classList.toggle('hidden', !el.dataset.for.split(' ').includes(kind.value));
          }
          document.getElementById('userLabel').textContent = kind.value === 'komga' ? 'Email' : 'Username';
        }
        kind.onchange = show; show();
        document.getElementById('f').onsubmit = async (e) => {
          e.preventDefault();
          const out = document.getElementById('result');
          const v = (id) => document.getElementById(id).value;
          const body = {kind: kind.value, name: v('name'), address: v('address'),
            alternateAddresses: [...document.querySelectorAll('.alt')].map(i => i.value).filter(Boolean),
            apiKey: v('apiKey'), username: v('username'), password: v('password')};
          out.textContent = 'Sending…';
          try {
            const r = await fetch('/\(code)/submit', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
            out.textContent = await r.text();
          } catch (err) { out.textContent = 'The Apple TV didn\\'t answer. Keep the setup screen open and try again.'; }
        };
        </script>
        </body></html>
        """
    }
}

#if canImport(Network)
/// Serves `PhoneSetupHTTP` on the local network while the setup screen is open.
public final class PhoneSetupServer: @unchecked Sendable {
    public let code: String
    private let server: LocalHTTPServer

    public init(code: String = BackupHTTP.makeCode(), context: PhoneSetupHTTP.Context,
                submit: @escaping @Sendable (PhoneSetupHTTP.Submission) async -> Result<String, Error>) {
        self.code = code
        self.server = LocalHTTPServer { request in
            await PhoneSetupHTTP.route(request, code: code, context: context, submit: { await submit($0) })
        }
    }

    /// Starts listening and returns the port (8791 when it's free).
    public func start(preferredPort: UInt16 = 8791) async throws -> UInt16 {
        try await server.start(preferredPort: preferredPort)
    }

    public func stop() {
        server.stop()
    }
}
#endif
