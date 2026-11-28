import Foundation

/// One entry in a book's table of contents.
public struct BookTOCEntry: Hashable, Sendable, Identifiable {
    public var title: String
    /// Section (spine item) the entry opens, zero-based.
    public var section: Int
    /// Anchor id inside the section, when the entry points mid-section.
    public var anchor: String?
    public var children: [BookTOCEntry]

    public var id: String { "\(section)|\(anchor ?? "")|\(title)" }

    public init(title: String, section: Int, anchor: String? = nil, children: [BookTOCEntry] = []) {
        self.title = title
        self.section = section
        self.anchor = anchor
        self.children = children
    }

    /// Depth-first list with each entry's nesting level, for a flat menu.
    public static func flatten(_ entries: [BookTOCEntry], level: Int = 0) -> [(entry: BookTOCEntry, level: Int)] {
        entries.flatMap { e in [(e, level)] + flatten(e.children, level: level + 1) }
    }
}

/// What the book reader needs up front.
public struct BookManifest: Hashable, Sendable {
    public var title: String
    /// Number of sections (EPUB spine items). Kavita calls these pages.
    public var sectionCount: Int
    public var toc: [BookTOCEntry]
    /// Every section is a single picture (a comic or manga packed as an
    /// EPUB). The app opens these in the image readers instead, through
    /// the server's `pages(for:)`.
    public var isImageOnly: Bool

    public init(title: String, sectionCount: Int, toc: [BookTOCEntry] = [], isImageOnly: Bool = false) {
        self.title = title
        self.sectionCount = sectionCount
        self.toc = toc
        self.isImageOnly = isImageOnly
    }
}

/// A run of text with inline styling.
public struct TextRun: Hashable, Sendable {
    public struct Style: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let bold = Style(rawValue: 1 << 0)
        public static let italic = Style(rawValue: 1 << 1)
        public static let monospace = Style(rawValue: 1 << 2)
        public static let raised = Style(rawValue: 1 << 3)
        public static let lowered = Style(rawValue: 1 << 4)
        public static let underline = Style(rawValue: 1 << 5)
        public static let strikethrough = Style(rawValue: 1 << 6)
        public static let smallCaps = Style(rawValue: 1 << 7)
    }

    public var text: String
    public var style: Style

    public init(_ text: String, style: Style = []) {
        self.text = text
        self.style = style
    }
}

public enum BlockAlignment: String, Hashable, Sendable {
    case natural
    case center
    case right
}

/// One block of reflowable content.
public enum BookBlock: Hashable, Sendable {
    /// `level` 1...6.
    case heading(level: Int, runs: [TextRun], anchor: String?)
    case paragraph(runs: [TextRun], alignment: BlockAlignment, anchor: String?)
    /// Indented quotation or poetry stanza.
    case quote(runs: [TextRun], anchor: String?)
    /// List item. `marker` is "•" or "3." etc. `depth` starts at 1.
    case listItem(marker: String, depth: Int, runs: [TextRun])
    /// Preformatted text: whitespace kept, monospace.
    case preformatted(String)
    case image(url: URL, alt: String?)
    /// Horizontal rule / scene break.
    case rule

    /// The text, without styling (tests, search, accessibility).
    public var plainText: String {
        switch self {
        case .heading(_, let runs, _), .paragraph(let runs, _, _), .quote(let runs, _), .listItem(_, _, let runs):
            return runs.map(\.text).joined()
        case .preformatted(let s): return s
        case .image(_, let alt): return alt ?? ""
        case .rule: return ""
        }
    }

    public var anchor: String? {
        switch self {
        case .heading(_, _, let a), .paragraph(_, _, let a), .quote(_, let a): return a
        default: return nil
        }
    }
}

/// One section of a book, parsed.
public struct BookSection: Hashable, Sendable {
    public var index: Int
    public var blocks: [BookBlock]

    public init(index: Int, blocks: [BookBlock]) {
        self.index = index
        self.blocks = blocks
    }

    public var imageURLs: [URL] {
        blocks.compactMap { if case .image(let url, _) = $0 { return url } else { return nil } }
    }

    /// Index of the first block carrying `anchor` (or containing it), if any.
    public func blockIndex(forAnchor anchor: String) -> Int? {
        blocks.firstIndex { $0.anchor == anchor }
    }
}

/// A backend that can serve reflowable books (EPUB, plain text) section by
/// section. `KavitaClient` implements it with Kavita's book API. Image-only
/// backends (Suwayomi) don't conform, and their chapters never have a text
/// format.
public protocol BookProviding: MangaServer {
    func bookManifest(for chapter: Chapter) async throws -> BookManifest
    /// Section `index` (zero-based) of a text chapter. Image URLs inside
    /// are absolute and load through `imageRequest(_:)`.
    func bookSection(_ index: Int, of chapter: Chapter) async throws -> BookSection
}
