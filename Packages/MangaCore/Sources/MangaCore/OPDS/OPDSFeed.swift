import Foundation

/// One OPDS catalog page, from either OPDS 1.2 (Atom XML) or OPDS 2.0
/// (JSON). Every URL is already resolved against the page's own URL.
public struct OPDSFeed: Hashable, Sendable {
    public var title: String
    public var entries: [OPDSEntry]
    /// Feed-level links: next, search, start, self…
    public var links: [OPDSLink]
    /// OPDS 2 groups ("Keep Reading", "Libraries"…). Their entries are also
    /// in `entries`; `topLevel` holds only the feed's own.
    public var groups: [OPDSGroup]
    public var topLevel: [OPDSEntry]

    public init(title: String, entries: [OPDSEntry], links: [OPDSLink], groups: [OPDSGroup] = [],
                topLevel: [OPDSEntry]? = nil) {
        self.title = title
        self.entries = entries
        self.links = links
        self.groups = groups
        self.topLevel = topLevel ?? entries
    }

    public var nextURL: URL? { links.first { $0.rel == "next" }?.href }

    /// OPDS 1 OpenSearch description, or an OPDS 2 templated search link.
    public var searchLink: OPDSLink? { links.first { $0.rel == "search" } }

    public var publications: [OPDSEntry] { entries.filter(\.isPublication) }
    public var navigationEntries: [OPDSEntry] { entries.filter { !$0.isPublication && $0.navigationURL != nil } }
}

public struct OPDSGroup: Hashable, Sendable {
    public var title: String
    /// The group's own feed (its `self` link), when it has one.
    public var url: URL?
    public var entries: [OPDSEntry]

    public init(title: String, url: URL?, entries: [OPDSEntry]) {
        self.title = title
        self.url = url
        self.entries = entries
    }
}

public struct OPDSLink: Hashable, Sendable {
    public var href: URL
    public var rel: String?
    public var type: String?
    public var title: String?
    /// OPDS-PSE page count (`pse:count`).
    public var pseCount: Int?
    /// OPDS-PSE last read page (`pse:lastRead`), as the server sent it.
    public var pseLastRead: Int?
    /// OPDS 2 `templated: true` (an RFC 6570 URI template).
    public var templated: Bool
    /// The absolute href with any `{…}` template braces left as typed
    /// (`URL` would percent-encode them). Nil when there are none.
    public var template: String?

    public init(href: URL, rel: String? = nil, type: String? = nil, title: String? = nil, pseCount: Int? = nil,
                pseLastRead: Int? = nil, templated: Bool = false, template: String? = nil) {
        self.template = template
        self.href = href
        self.rel = rel
        self.type = type
        self.title = title
        self.pseCount = pseCount
        self.pseLastRead = pseLastRead
        self.templated = templated
    }

    /// The media type without parameters, lower-cased.
    public var baseType: String {
        (type ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
    }

    var isFeedType: Bool {
        let t = baseType
        return t == "application/atom+xml" || t == "application/opds+json" || t.isEmpty
    }
}

public struct OPDSEntry: Hashable, Sendable {
    public var id: String
    public var title: String
    public var summary: String?
    public var authors: [String]
    public var categories: [String]
    public var updated: Date?
    public var links: [OPDSLink]
    /// OPDS 2 publication images (OPDS 1 images are links).
    public var images: [URL]
    /// OPDS 2: number of pages, when the server says.
    public var numberOfPages: Int?

    public init(id: String, title: String, summary: String? = nil, authors: [String] = [], categories: [String] = [],
                updated: Date? = nil, links: [OPDSLink] = [], images: [URL] = [], numberOfPages: Int? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.authors = authors
        self.categories = categories
        self.updated = updated
        self.links = links
        self.images = images
        self.numberOfPages = numberOfPages
    }

    public static let pseRel = "http://vaemendis.net/opds-pse/stream"
    static let acquisitionPrefix = "http://opds-spec.org/acquisition"

    /// Page streaming (OPDS-PSE): a URL template with `{pageNumber}`.
    public var pseLink: OPDSLink? { links.first { $0.rel == Self.pseRel } }

    /// OPDS 2 DiViNa manifest: a JSON list of page images with sizes.
    public var divinaManifest: URL? {
        links.first { $0.baseType == "application/divina+json" }?.href
    }

    /// Downloadable files, open access first.
    public var acquisitions: [OPDSLink] {
        let all = links.filter { ($0.rel ?? "").hasPrefix(Self.acquisitionPrefix) }
        let open = all.filter { $0.rel == Self.acquisitionPrefix + "/open-access" }
        return open + all.filter { $0.rel != Self.acquisitionPrefix + "/open-access" }
    }

    /// The best file to download for reading, by format preference.
    public var preferredAcquisition: OPDSLink? {
        let ranked = acquisitions.map { ($0, ContentKind(mediaType: $0.baseType, url: $0.href)) }
        for kind in [ContentKind.comicArchive, .pdf, .epub] {
            if let match = ranked.first(where: { $0.1 == kind }) { return match.0 }
        }
        return acquisitions.first
    }

    public var isPublication: Bool { pseLink != nil || divinaManifest != nil || !acquisitions.isEmpty }

    /// Where a navigation entry leads (`subsection`, a catalog link, or any
    /// feed-typed link).
    public var navigationURL: URL? {
        let candidates = links.filter { !($0.rel ?? "").hasPrefix(Self.acquisitionPrefix) && $0.rel != Self.pseRel }
        let preferred = candidates.first { link in
            let rel = link.rel ?? ""
            return link.isFeedType && (rel == "subsection" || rel.isEmpty || rel == "alternate" || rel.hasPrefix("http://opds-spec.org/sort")
                || rel == "http://opds-spec.org/crawlable" || rel == "collection" || rel == "related")
        }
        return (preferred ?? candidates.first { $0.isFeedType && !$0.baseType.isEmpty })?.href
    }

    /// Thumbnail first, then full image.
    public var coverURL: URL? {
        let thumb = links.first { $0.rel == "http://opds-spec.org/image/thumbnail" || $0.rel == "http://opds-spec.org/thumbnail" }
        let image = links.first { $0.rel == "http://opds-spec.org/image" || $0.rel == "http://opds-spec.org/cover" }
        return thumb?.href ?? images.first ?? image?.href
    }
}

/// What kind of file an acquisition link points at.
public enum ContentKind: Equatable, Sendable {
    case comicArchive
    case pdf
    case epub
    case other

    public init(mediaType: String, url: URL?) {
        let ext = url?.pathExtension.lowercased() ?? ""
        switch mediaType {
        case "application/zip", "application/x-zip-compressed", "application/vnd.comicbook+zip", "application/x-cbz",
             "application/vnd.comicbook-zip":
            self = .comicArchive
        case "application/pdf": self = .pdf
        case "application/epub+zip": self = .epub
        default:
            switch ext {
            case "cbz", "zip": self = .comicArchive
            case "pdf": self = .pdf
            case "epub": self = .epub
            default: self = .other
            }
        }
    }
}
