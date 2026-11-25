import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses OPDS 1.2 (Atom) and OPDS 2.0 (JSON) feeds into `OPDSFeed`, and
/// OpenSearch descriptions. Relative links resolve against `baseURL`.
public enum OPDSParser {
    public enum Format: Equatable, Sendable { case atom, json }

    /// Picks the format from the Content-Type, falling back to sniffing.
    public static func format(contentType: String?, data: Data) -> Format? {
        let type = contentType?.lowercased() ?? ""
        if type.contains("json") { return .json }
        if type.contains("xml") { return .atom }
        guard let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) }) else {
            return nil
        }
        if first == UInt8(ascii: "{") { return .json }
        if first == UInt8(ascii: "<") {
            // An HTML page (a web UI, a login form) isn't a feed.
            let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
            return head.contains("<feed") || head.contains("<?xml") ? .atom : nil
        }
        return nil
    }

    public static func parse(_ data: Data, contentType: String?, baseURL: URL) throws -> OPDSFeed {
        switch format(contentType: contentType, data: data) {
        case .json: return try parseJSON(data, baseURL: baseURL)
        case .atom: return try parseAtom(data, baseURL: baseURL)
        case nil: throw MangaError.decoding("This address doesn't serve an OPDS catalog.")
        }
    }

    static func resolve(_ href: String?, _ base: URL) -> URL? {
        guard let href = href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty else { return nil }
        // Keep URI template braces intact ({pageNumber}, {?query}).
        let escaped = href.replacingOccurrences(of: " ", with: "%20")
        if let url = URL(string: escaped, relativeTo: base) { return url.absoluteURL }
        let encoded = escaped.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(CharacterSet(charactersIn: "{}#%")))
        return encoded.flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
    }

    /// `href` made absolute as a string, so URI template braces survive.
    static func absoluteString(_ href: String, _ base: URL) -> String {
        let h = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil { return h }
        let scheme = base.scheme ?? "http"
        if h.hasPrefix("//") { return scheme + ":" + h }
        var origin = scheme + "://" + (base.host ?? "")
        if let port = base.port { origin += ":\(port)" }
        if h.hasPrefix("/") { return origin + h }
        var dir = base.path
        if !base.hasDirectoryPath { dir = (dir as NSString).deletingLastPathComponent }
        if !dir.hasSuffix("/") { dir += "/" }
        return origin + dir + h
    }

    /// A link with its `template` filled in when the href has `{…}`.
    static func link(href raw: String?, base: URL, rel: String?, type: String?, title: String?, pseCount: Int? = nil,
                     pseLastRead: Int? = nil, templated: Bool = false) -> OPDSLink? {
        guard let raw, let href = resolve(raw, base) else { return nil }
        let template = raw.contains("{") ? absoluteString(raw, base) : nil
        return OPDSLink(href: href, rel: rel, type: type, title: title, pseCount: pseCount, pseLastRead: pseLastRead,
                        templated: templated || template != nil, template: template)
    }

    // MARK: Atom

    public static func parseAtom(_ data: Data, baseURL: URL) throws -> OPDSFeed {
        let delegate = AtomDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.delegate = delegate
        guard parser.parse(), delegate.sawFeed else {
            let reason = parser.parserError.map { String(describing: $0) } ?? "not an Atom feed"
            throw MangaError.decoding("Couldn't read the OPDS feed (\(reason)).")
        }
        return OPDSFeed(title: delegate.feedTitle, entries: delegate.entries, links: delegate.feedLinks)
    }

    final class AtomDelegate: NSObject, XMLParserDelegate {
        let baseURL: URL
        var sawFeed = false
        var feedTitle = ""
        var feedLinks: [OPDSLink] = []
        var entries: [OPDSEntry] = []

        private var entry: OPDSEntry?
        private var text = ""
        private var inAuthor = false
        private var depth = 0
        private var entryDepth = 0

        init(baseURL: URL) { self.baseURL = baseURL }

        /// Attribute by local name, whatever prefix the server used.
        static func attribute(_ name: String, in attributes: [String: String]) -> String? {
            if let v = attributes[name] { return v }
            return attributes.first { $0.key.hasSuffix(":" + name) }?.value
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            depth += 1
            text = ""
            let local = name.split(separator: ":").last.map(String.init) ?? name
            switch local {
            case "feed":
                sawFeed = true
            case "entry":
                entry = OPDSEntry(id: "", title: "")
                entryDepth = depth
            case "author":
                inAuthor = true
            case "category":
                if let label = Self.attribute("label", in: attributes) ?? Self.attribute("term", in: attributes), !label.isEmpty {
                    entry?.categories.append(label)
                }
            case "link":
                guard let link = OPDSParser.link(
                    href: Self.attribute("href", in: attributes), base: baseURL,
                    rel: Self.attribute("rel", in: attributes),
                    type: Self.attribute("type", in: attributes),
                    title: Self.attribute("title", in: attributes),
                    pseCount: Self.attribute("count", in: attributes).flatMap { Int($0) },
                    pseLastRead: Self.attribute("lastRead", in: attributes).flatMap { Int($0) }) else { return }
                if entry != nil { entry?.links.append(link) } else { feedLinks.append(link) }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { depth -= 1 }
            let local = name.split(separator: ":").last.map(String.init) ?? name
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            guard entry != nil else {
                if local == "title", depth == 2 { feedTitle = value }
                return
            }
            switch local {
            case "entry":
                if var finished = entry {
                    if finished.id.isEmpty { finished.id = finished.navigationURL?.absoluteString ?? finished.title }
                    entries.append(finished)
                }
                entry = nil
            case "title" where depth == entryDepth + 1:
                entry?.title = value
            case "id" where depth == entryDepth + 1:
                entry?.id = value
            case "name" where inAuthor:
                if !value.isEmpty { entry?.authors.append(value) }
            case "author":
                inAuthor = false
            case "summary", "content":
                if !value.isEmpty, entry?.summary == nil || local == "summary" { entry?.summary = OPDSParser.plainText(value) }
            case "updated" where depth == entryDepth + 1:
                entry?.updated = DateParsing.parse(value)
            default:
                break
            }
        }
    }

    /// Strips tags from an HTML summary.
    static func plainText(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var out = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; out.append(" "); continue }
            if !inTag { out.append(ch) }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: OpenSearch

    /// The Atom search URL template from an OpenSearch description
    /// (`…{searchTerms}…`).
    public static func openSearchTemplate(_ data: Data, baseURL: URL) -> String? {
        let delegate = OpenSearchDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        _ = parser.parse()
        let urls = delegate.urls
        let atom = urls.first { ($0.type ?? "").contains("atom") } ?? urls.first
        guard let template = atom?.template else { return nil }
        return absoluteString(template, baseURL)
    }

    final class OpenSearchDelegate: NSObject, XMLParserDelegate {
        var urls: [(template: String, type: String?)] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "Url" || name.hasSuffix(":Url"), let template = attributes["template"] {
                urls.append((template, attributes["type"]))
            }
        }
    }

    // MARK: OPDS 2

    public static func parseJSON(_ data: Data, baseURL: URL) throws -> OPDSFeed {
        let doc: OPDS2Feed
        do {
            doc = try JSONDecoder().decode(OPDS2Feed.self, from: data)
        } catch {
            throw MangaError.decoding("Couldn't read the OPDS 2 feed: \(error)")
        }
        func links(_ list: [OPDS2Link]?) -> [OPDSLink] {
            (list ?? []).compactMap { l in
                link(href: l.href, base: baseURL, rel: l.rel?.first, type: l.type, title: l.title,
                     templated: l.templated ?? false)
            }
        }
        func navigation(_ list: [OPDS2Link]?) -> [OPDSEntry] {
            links(list).map { link in
                var nav = link
                if nav.rel == nil || nav.rel == "self" { nav.rel = "subsection" }
                return OPDSEntry(id: link.href.absoluteString, title: link.title ?? "Untitled", links: [nav])
            }
        }
        func publications(_ list: [OPDS2Publication]?) -> [OPDSEntry] {
            (list ?? []).map { p in
                let entryLinks = links(p.links)
                let id = p.metadata.identifier ?? entryLinks.first { $0.rel == "self" }?.href.absoluteString ?? p.metadata.title
                let people = (p.metadata.author ?? []) + (p.metadata.contributor ?? []) + (p.metadata.penciler ?? [])
                var seen = Set<String>()
                return OPDSEntry(
                    id: id,
                    title: p.metadata.title,
                    summary: p.metadata.description.map(plainText),
                    authors: people.map(\.name).filter { seen.insert($0).inserted },
                    categories: (p.metadata.subject ?? []).map(\.name),
                    updated: (p.metadata.modified ?? p.metadata.published).flatMap(DateParsing.parse),
                    links: entryLinks,
                    images: (p.images ?? []).compactMap { resolve($0.href, baseURL) },
                    numberOfPages: p.metadata.numberOfPages)
            }
        }
        let top = navigation(doc.navigation) + publications(doc.publications)
        var entries = top
        var groups: [OPDSGroup] = []
        for group in doc.groups ?? [] {
            let items = navigation(group.navigation) + publications(group.publications)
            let selfURL = links(group.links).first { $0.rel == "self" }?.href
            groups.append(OPDSGroup(title: group.metadata?.title ?? "", url: selfURL, entries: items))
            entries += items
        }
        // Groups often repeat what the feed already lists.
        var seen = Set<String>()
        entries = entries.filter { seen.insert($0.id).inserted }
        return OPDSFeed(title: doc.metadata?.title ?? "", entries: entries, links: links(doc.links), groups: groups,
                        topLevel: top)
    }
}

// MARK: OPDS 2 JSON shapes

struct OPDS2Feed: Decodable {
    struct Metadata: Decodable { var title: String? }
    struct Group: Decodable {
        var metadata: Metadata?
        var links: [OPDS2Link]?
        var navigation: [OPDS2Link]?
        var publications: [OPDS2Publication]?
    }
    var metadata: Metadata?
    var links: [OPDS2Link]?
    var navigation: [OPDS2Link]?
    var publications: [OPDS2Publication]?
    var groups: [Group]?
}

struct OPDS2Link: Decodable {
    var href: String?
    var rel: [String]?
    var type: String?
    var title: String?
    var templated: Bool?
    var width: Double?
    var height: Double?

    enum CodingKeys: String, CodingKey { case href, rel, type, title, templated, width, height }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        href = try c.decodeIfPresent(String.self, forKey: .href)
        // `rel` is a string or an array of strings.
        if let one = try? c.decodeIfPresent(String.self, forKey: .rel) {
            rel = [one]
        } else {
            rel = try? c.decodeIfPresent([String].self, forKey: .rel)
        }
        type = try c.decodeIfPresent(String.self, forKey: .type)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        templated = try? c.decodeIfPresent(Bool.self, forKey: .templated)
        width = try? c.decodeIfPresent(Double.self, forKey: .width)
        height = try? c.decodeIfPresent(Double.self, forKey: .height)
    }
}

struct OPDS2Publication: Decodable {
    struct Metadata: Decodable {
        var title: String
        var identifier: String?
        var description: String?
        var modified: String?
        var published: String?
        var numberOfPages: Int?
        var author: [OPDS2Contributor]?
        var contributor: [OPDS2Contributor]?
        var penciler: [OPDS2Contributor]?
        var subject: [OPDS2Contributor]?

        enum CodingKeys: String, CodingKey {
            case title, identifier, description, modified, published, numberOfPages, author, contributor, penciler, subject
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
            identifier = try? c.decodeIfPresent(String.self, forKey: .identifier)
            description = try? c.decodeIfPresent(String.self, forKey: .description)
            modified = try? c.decodeIfPresent(String.self, forKey: .modified)
            published = try? c.decodeIfPresent(String.self, forKey: .published)
            numberOfPages = try? c.decodeIfPresent(Int.self, forKey: .numberOfPages)
            author = OPDS2Contributor.list(c, .author)
            contributor = OPDS2Contributor.list(c, .contributor)
            penciler = OPDS2Contributor.list(c, .penciler)
            subject = OPDS2Contributor.list(c, .subject)
        }
    }
    var metadata: Metadata
    var links: [OPDS2Link]?
    var images: [OPDS2Link]?
}

/// A contributor or subject: a string, an object with `name`, or a list of either.
struct OPDS2Contributor: Decodable {
    var name: String

    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            name = s
            return
        }
        struct Named: Decodable { var name: String }
        name = try Named(from: decoder).name
    }

    static func list<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [OPDS2Contributor]? {
        if let many = try? c.decodeIfPresent([OPDS2Contributor].self, forKey: key) { return many }
        if let one = try? c.decodeIfPresent(OPDS2Contributor.self, forKey: key) { return [one] }
        return nil
    }
}

/// A Readium WebPub / DiViNa manifest's page list.
struct DivinaManifest: Decodable {
    var readingOrder: [OPDS2Link]
}
