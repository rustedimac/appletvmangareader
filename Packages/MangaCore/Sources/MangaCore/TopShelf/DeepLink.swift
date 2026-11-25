import Foundation

/// A link into the app, used by Top Shelf items.
///
///     mangareader://series?server=<uuid>&series=<id>&profile=<uuid>
///     mangareader://read?server=<uuid>&series=<id>&chapter=<id>&page=<n>&profile=<uuid>
///
/// `profile` is the profile the item was made for; opening the link
/// switches to it. `page` is zero-based and optional.
public enum DeepLink: Hashable, Sendable {
    /// Open a series' detail page.
    case series(SeriesRef, profile: UUID?)
    /// Open the reader on a chapter.
    case read(SeriesRef, chapterID: String, page: Int?, profile: UUID?)

    public static let scheme = "mangareader"

    public var ref: SeriesRef {
        switch self {
        case .series(let ref, _), .read(let ref, _, _, _): return ref
        }
    }

    public var profile: UUID? {
        switch self {
        case .series(_, let p), .read(_, _, _, let p): return p
        }
    }

    public var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        var items = [URLQueryItem(name: "server", value: ref.serverID.uuidString),
                     URLQueryItem(name: "series", value: ref.seriesID)]
        switch self {
        case .series:
            c.host = "series"
        case .read(_, let chapterID, let page, _):
            c.host = "read"
            items.append(URLQueryItem(name: "chapter", value: chapterID))
            if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        }
        if let profile { items.append(URLQueryItem(name: "profile", value: profile.uuidString)) }
        c.queryItems = items
        return c.url!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var q: [String: String] = [:]
        for item in c.queryItems ?? [] { if let v = item.value { q[item.name] = v } }
        guard let server = q["server"].flatMap(UUID.init(uuidString:)),
              let series = q["series"], !series.isEmpty else { return nil }
        let ref = SeriesRef(serverID: server, seriesID: series)
        let profile = q["profile"].flatMap(UUID.init(uuidString:))
        switch c.host?.lowercased() {
        case "series":
            self = .series(ref, profile: profile)
        case "read":
            guard let chapter = q["chapter"], !chapter.isEmpty else { return nil }
            let page = q["page"].flatMap(Int.init).map { max(0, $0) }
            self = .read(ref, chapterID: chapter, page: page, profile: profile)
        default:
            return nil
        }
    }
}
