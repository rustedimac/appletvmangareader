import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// An EPUB unpacked into a folder (`LocalArchiveCache.epub`), read on
/// device for servers that only hand out the whole file (OPDS catalogs,
/// Calibre). Kavita doesn't need this: it serves EPUBs section by section.
///
/// Reads `META-INF/container.xml`, the package document (OPF) for the
/// title, manifest and spine, and the table of contents from the EPUB 3
/// navigation document or the EPUB 2 NCX. Sections are spine items, so a
/// section index means the same thing here as it does for Kavita.
public struct EPUBPackage: Hashable, Sendable {
    /// One spine item.
    public struct Item: Hashable, Sendable {
        public var url: URL
        public var mediaType: String
    }

    public var title: String
    public var authors: [String]
    public var sections: [Item]
    public var toc: [BookTOCEntry]
    /// Every section is just a picture (comics and manga made into EPUBs,
    /// e.g. by Kindle Comic Converter). These read better as pages.
    public var imagePages: [URL]?

    public var manifest: BookManifest {
        BookManifest(title: title, sectionCount: sections.count, toc: toc, isImageOnly: imagePages != nil)
    }

    public enum EPUBError: Error, LocalizedError, Equatable {
        case missing(String)
        case empty

        public var errorDescription: String? {
            switch self {
            case .missing(let what): return "The EPUB is damaged (no \(what))."
            case .empty: return "The EPUB has nothing to read."
            }
        }
    }

    /// Reads the package in `folder` (the unzipped EPUB).
    public init(folder: URL) throws {
        let container = folder.appendingPathComponent("META-INF/container.xml")
        guard let containerData = FileManager.default.contents(atPath: container.path) else {
            throw EPUBError.missing("container.xml")
        }
        let rootPath = XMLScan.firstAttribute("full-path", ofElement: "rootfile", in: containerData) ?? ""
        guard !rootPath.isEmpty, let opfURL = Self.resolve(rootPath, relativeTo: folder.appendingPathComponent("x")),
              Self.isInside(opfURL, folder), let opfData = FileManager.default.contents(atPath: opfURL.path) else {
            throw EPUBError.missing("package document")
        }
        let opf = OPFDocument(opfData)
        var byID: [String: (url: URL, type: String, properties: String)] = [:]
        for item in opf.manifest {
            guard let url = Self.resolve(item.href, relativeTo: opfURL), Self.isInside(url, folder) else { continue }
            byID[item.id] = (url, item.mediaType, item.properties)
        }
        sections = opf.spine.compactMap { idref in
            byID[idref].map { Item(url: $0.url, mediaType: $0.type) }
        }.filter { $0.mediaType.contains("html") || $0.mediaType.contains("xml") || $0.mediaType.hasPrefix("image/") }
        guard !sections.isEmpty else { throw EPUBError.empty }
        title = opf.title ?? ""
        authors = opf.creators

        // Table of contents: EPUB 3 nav first, then the NCX.
        let indexByPath = Dictionary(sections.enumerated().map { (Self.key($1.url), $0) }, uniquingKeysWith: { a, _ in a })
        var entries: [BookTOCEntry] = []
        if let nav = byID.values.first(where: { $0.properties.split(separator: " ").contains("nav") }),
           let data = FileManager.default.contents(atPath: nav.url.path) {
            entries = NavDocument.entries(String(decoding: data, as: UTF8.self), base: nav.url, sections: indexByPath)
        }
        if entries.isEmpty, let ncxID = opf.tocID ?? byID.first(where: { $0.value.type == "application/x-dtbncx+xml" })?.key,
           let ncx = byID[ncxID], let data = FileManager.default.contents(atPath: ncx.url.path) {
            entries = NCXDocument(data, base: ncx.url, sections: indexByPath).entries
        }
        toc = entries
        imagePages = Self.imageOnlyPages(sections)
    }

    /// Section `index` as blocks, images pointing at files in the folder.
    public func section(_ index: Int) throws -> BookSection {
        guard sections.indices.contains(index) else { throw MangaError.notFound }
        let item = sections[index]
        if item.mediaType.hasPrefix("image/") {
            return BookSection(index: index, blocks: [.image(url: item.url, alt: nil)])
        }
        guard let data = FileManager.default.contents(atPath: item.url.path) else { throw EPUBError.missing("section \(index + 1)") }
        let parser = HTMLBookParser(resolveURL: { src in
            guard let url = Self.resolve(src, relativeTo: item.url) else { return nil }
            return url.isFileURL || url.scheme == "http" || url.scheme == "https" ? url : nil
        })
        return parser.parse(Self.body(of: String(decoding: data, as: UTF8.self)), section: index)
    }

    /// The `<body>` of an XHTML document, so the head's title and styles
    /// don't show up as text.
    static func body(of html: String) -> String {
        guard let start = html.range(of: "<body", options: .caseInsensitive) else { return html }
        var rest = html[start.lowerBound...]
        if let end = rest.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            rest = rest[..<end.upperBound]
        }
        return String(rest)
    }

    /// Picture-only books: every section is an image, or an XHTML page
    /// holding one image and next to no text.
    static func imageOnlyPages(_ sections: [Item]) -> [URL]? {
        var pages: [URL] = []
        for item in sections {
            if item.mediaType.hasPrefix("image/") {
                pages.append(item.url)
                continue
            }
            guard let data = FileManager.default.contents(atPath: item.url.path) else { return nil }
            var images: [String] = []
            var textCount = 0
            var inBody = false
            for token in HTMLTokenizer(String(decoding: data, as: UTF8.self)) {
                switch token {
                case .start(let name, let attributes, _):
                    if name == "body" { inBody = true }
                    if inBody, name == "img", let src = attributes["src"] { images.append(src) }
                    if inBody, name == "image", let src = attributes["href"] ?? attributes["xlink:href"] { images.append(src) }
                case .text(let text) where inBody:
                    textCount += text.trimmingCharacters(in: .whitespacesAndNewlines).count
                default:
                    break
                }
            }
            guard images.count == 1, textCount < 40, let url = resolve(images[0], relativeTo: item.url) else { return nil }
            pages.append(url)
        }
        return pages.isEmpty ? nil : pages
    }

    // MARK: Paths

    static func resolve(_ href: String, relativeTo base: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutFragment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        guard !withoutFragment.isEmpty else { return nil }
        if let absolute = URL(string: withoutFragment), absolute.scheme != nil { return absolute }
        let escaped = withoutFragment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(["%"])) ?? withoutFragment
        return URL(string: escaped, relativeTo: base)?.absoluteURL.standardizedFileURL
    }

    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path)
    }

    /// Path key for matching TOC links to spine items.
    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.removingPercentEncoding ?? url.standardizedFileURL.path
    }

    static func fragment(_ href: String) -> String? {
        guard let hash = href.firstIndex(of: "#") else { return nil }
        let f = String(href[href.index(after: hash)...])
        return f.isEmpty ? nil : (f.removingPercentEncoding ?? f)
    }
}

// MARK: - Package document

struct OPFDocument {
    struct ManifestItem { var id: String; var href: String; var mediaType: String; var properties: String }
    var title: String?
    var creators: [String] = []
    var manifest: [ManifestItem] = []
    var spine: [String] = []
    var tocID: String?

    init(_ data: Data) {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        parser.parse()
        title = delegate.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        creators = delegate.creators.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        manifest = delegate.manifest
        spine = delegate.spine
        tocID = delegate.tocID
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var title: String?
        var creators: [String] = []
        var manifest: [ManifestItem] = []
        var spine: [String] = []
        var tocID: String?
        private var text = ""
        private var capturing = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            switch XMLScan.local(elementName) {
            case "title" where title == nil, "creator":
                capturing = true
                text = ""
            case "item":
                if let id = attributes["id"], let href = attributes["href"] {
                    manifest.append(ManifestItem(id: id, href: href, mediaType: attributes["media-type"] ?? "",
                                                 properties: attributes["properties"] ?? ""))
                }
            case "spine":
                tocID = attributes["toc"]
            case "itemref":
                if let idref = attributes["idref"] { spine.append(idref) }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard capturing else { return }
            switch XMLScan.local(elementName) {
            case "title": title = text; capturing = false
            case "creator": creators.append(text); capturing = false
            default: break
            }
        }
    }
}

// MARK: - Tables of contents

/// The EPUB 3 navigation document's `<nav epub:type="toc">` list.
enum NavDocument {
    static func entries(_ html: String, base: URL, sections: [String: Int]) -> [BookTOCEntry] {
        var inTOC = false
        var navDepth = 0
        var inLink = false
        var lists: [[BookTOCEntry]] = []
        var items: [(href: String?, title: String, children: [BookTOCEntry])] = []
        var result: [BookTOCEntry] = []

        func entry(href: String?, title: String, children: [BookTOCEntry]) -> BookTOCEntry? {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let section = href.flatMap { EPUBPackage.resolve($0, relativeTo: base) }.flatMap { sections[EPUBPackage.key($0)] }
            guard let section else {
                // An entry without a target in the spine still groups its children.
                return children.first.map { BookTOCEntry(title: trimmed, section: $0.section, children: children) }
            }
            return BookTOCEntry(title: trimmed.isEmpty ? "Section \(section + 1)" : trimmed, section: section,
                                anchor: href.flatMap(EPUBPackage.fragment), children: children)
        }

        for token in HTMLTokenizer(html) {
            switch token {
            case .start(let name, let attributes, let selfClosing):
                if name == "nav" {
                    if inTOC { navDepth += 1; continue }
                    let type = attributes["epub:type"] ?? attributes["type"] ?? attributes["role"] ?? ""
                    if type.contains("toc") { inTOC = true; navDepth = 1 }
                    continue
                }
                guard inTOC, !selfClosing else { continue }
                switch name {
                case "ol", "ul": lists.append([])
                case "li": items.append((nil, "", []))
                case "a", "span":
                    inLink = true
                    if name == "a", !items.isEmpty, items[items.count - 1].href == nil {
                        items[items.count - 1].href = attributes["href"]
                    }
                default: break
                }
            case .text(let text):
                if inTOC, inLink, !items.isEmpty { items[items.count - 1].title += text }
            case .end(let name):
                guard inTOC else { continue }
                switch name {
                case "a", "span": inLink = false
                case "ol", "ul":
                    let list = lists.popLast() ?? []
                    if items.isEmpty { result += list } else { items[items.count - 1].children += list }
                case "li":
                    guard let item = items.popLast(),
                          let e = entry(href: item.href, title: item.title, children: item.children) else { continue }
                    if lists.isEmpty { result.append(e) } else { lists[lists.count - 1].append(e) }
                case "nav":
                    navDepth -= 1
                    if navDepth <= 0 { return result }
                default: break
                }
            }
        }
        return result
    }
}

/// The EPUB 2 NCX `navMap`.
struct NCXDocument {
    var entries: [BookTOCEntry] = []

    init(_ data: Data, base: URL, sections: [String: Int]) {
        let delegate = Delegate(base: base, sections: sections)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        entries = delegate.root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let base: URL
        let sections: [String: Int]
        var root: [BookTOCEntry] = []
        private var stack: [(title: String, src: String?, children: [BookTOCEntry])] = []
        private var inText = false

        init(base: URL, sections: [String: Int]) {
            self.base = base
            self.sections = sections
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            switch XMLScan.local(elementName) {
            case "navPoint": stack.append(("", nil, []))
            case "text": inText = !stack.isEmpty
            case "content": if !stack.isEmpty, stack[stack.count - 1].src == nil { stack[stack.count - 1].src = attributes["src"] }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText, !stack.isEmpty, stack[stack.count - 1].children.isEmpty { stack[stack.count - 1].title += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch XMLScan.local(elementName) {
            case "text": inText = false
            case "navPoint":
                guard let point = stack.popLast() else { return }
                let title = point.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let section = point.src.flatMap { EPUBPackage.resolve($0, relativeTo: base) }.flatMap { sections[EPUBPackage.key($0)] }
                let entry: BookTOCEntry?
                if let section {
                    entry = BookTOCEntry(title: title.isEmpty ? "Section \(section + 1)" : title, section: section,
                                         anchor: point.src.flatMap(EPUBPackage.fragment), children: point.children)
                } else if let first = point.children.first {
                    entry = BookTOCEntry(title: title, section: first.section, children: point.children)
                } else {
                    entry = nil
                }
                guard let entry else { return }
                if stack.isEmpty { root.append(entry) } else { stack[stack.count - 1].children.append(entry) }
            default: break
            }
        }
    }
}

/// Small helpers for XML that's read once.
enum XMLScan {
    static func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    static func firstAttribute(_ attribute: String, ofElement element: String, in data: Data) -> String? {
        final class Finder: NSObject, XMLParserDelegate {
            let attribute: String, element: String
            var found: String?
            init(_ a: String, _ e: String) { attribute = a; element = e }
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                        qualifiedName qName: String?, attributes: [String: String] = [:]) {
                if found == nil, XMLScan.local(elementName) == element, let v = attributes[attribute] {
                    found = v
                    parser.abortParsing()
                }
            }
        }
        let finder = Finder(attribute, element)
        let parser = XMLParser(data: data)
        parser.delegate = finder
        parser.parse()
        return finder.found
    }
}
