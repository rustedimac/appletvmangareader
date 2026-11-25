import Foundation

/// Turns an EPUB section's HTML into `BookBlock`s the book reader can lay
/// out. tvOS has no WebKit, so this is a small, forgiving tokenizer rather
/// than a browser: it understands the structure books use (headings,
/// paragraphs, quotes, lists, preformatted text, rules, images, line
/// breaks) and the inline styles that matter for reading (bold, italic,
/// monospace, raised/lowered, underline, strikethrough). Everything else
/// (scripts, styles, forms, unknown tags) is dropped or read as plain text.
///
/// Kavita's `book-page` HTML isn't always well-formed XML (unclosed `<p>`,
/// bare `&`), so nothing here depends on it being so.
public struct HTMLBookParser {
    /// Turns an `src`/`href` from the HTML into an absolute URL. Return nil
    /// to drop the image.
    public var resolveURL: (String) -> URL?

    public init(resolveURL: @escaping (String) -> URL? = { URL(string: $0) }) {
        self.resolveURL = resolveURL
    }

    public func parse(_ html: String, section: Int = 0) -> BookSection {
        var builder = BlockBuilder(resolveURL: resolveURL)
        for token in HTMLTokenizer(html) {
            builder.handle(token)
        }
        builder.finish()
        return BookSection(index: section, blocks: builder.blocks)
    }
}

/// Plain text: blank lines separate paragraphs, single newlines are kept
/// as line breaks only when the text looks like verse (short lines), and
/// otherwise joined, so hard-wrapped Project Gutenberg text reflows.
public enum PlainTextBookParser {
    public static func parse(_ text: String, section: Int = 0) -> BookSection {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var blocks: [BookBlock] = []
        var current: [String] = []

        func flush() {
            defer { current = [] }
            let lines = current.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            let isVerse = lines.count > 1 && lines.allSatisfy { $0.count < 50 }
            let joined = lines.joined(separator: isVerse ? "\n" : " ")
            if lines.count == 1, isRule(lines[0]) {
                blocks.append(.rule)
            } else {
                blocks.append(.paragraph(runs: [TextRun(joined)], alignment: .natural, anchor: nil))
            }
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush() } else { current.append(String(line)) }
        }
        flush()
        return BookSection(index: section, blocks: blocks)
    }

    static func isRule(_ line: String) -> Bool {
        let chars = Set(line.replacingOccurrences(of: " ", with: ""))
        return line.count >= 3 && chars.count == 1 && "*-_~=#".contains(chars.first!)
    }
}

// MARK: - Tokenizer

enum HTMLToken: Equatable {
    case text(String)
    case start(name: String, attributes: [String: String], selfClosing: Bool)
    case end(name: String)
}

/// Splits HTML into text, start tags and end tags. Skips comments,
/// doctypes and processing instructions, and swallows the contents of
/// `script` and `style` whole. Tag and attribute names come out lowercase
/// with any namespace prefix removed from tag names (`svg:image` → `image`).
struct HTMLTokenizer: Sequence, IteratorProtocol {
    private let s: [Unicode.Scalar]
    private var i = 0
    private var pendingRawTextEnd: String?

    init(_ html: String) {
        s = Array(html.unicodeScalars)
    }

    mutating func next() -> HTMLToken? {
        if let raw = pendingRawTextEnd {
            pendingRawTextEnd = nil
            skipRawText(until: raw)
        }
        while i < s.count {
            if s[i] == "<" {
                if let token = readMarkup() { return token }
                continue
            }
            return .text(readText())
        }
        return nil
    }

    private mutating func readText() -> String {
        var out = String.UnicodeScalarView()
        while i < s.count, s[i] != "<" {
            out.append(s[i])
            i += 1
        }
        return HTMLEntities.decode(String(out))
    }

    /// At a "<". Returns a tag token, or nil after skipping a comment or
    /// declaration. A "<" that doesn't start markup is returned as text.
    private mutating func readMarkup() -> HTMLToken? {
        let start = i
        if starts(with: "<!--") {
            i += 4
            skip(past: "-->")
            return nil
        }
        if starts(with: "<![CDATA[") {
            i += 9
            var out = String.UnicodeScalarView()
            while i < s.count, !starts(with: "]]>") { out.append(s[i]); i += 1 }
            i = min(s.count, i + 3)
            return .text(String(out))
        }
        if starts(with: "<!") || starts(with: "<?") {
            skip(past: ">")
            return nil
        }
        i += 1
        var closing = false
        if i < s.count, s[i] == "/" { closing = true; i += 1 }
        guard i < s.count, s[i].properties.isAlphabetic else {
            // Not a tag, e.g. "a < b".
            i = start + 1
            return .text("<")
        }
        let rawName = readName()
        let name = Self.localName(rawName)
        if closing {
            skip(past: ">")
            return .end(name: name)
        }
        var attributes: [String: String] = [:]
        var selfClosing = false
        while i < s.count {
            skipWhitespace()
            guard i < s.count else { break }
            if s[i] == ">" { i += 1; break }
            if s[i] == "/" {
                i += 1
                skipWhitespace()
                if i < s.count, s[i] == ">" { selfClosing = true; i += 1; break }
                continue
            }
            let attrName = readName().lowercased()
            if attrName.isEmpty { i += 1; continue }
            skipWhitespace()
            var value = ""
            if i < s.count, s[i] == "=" {
                i += 1
                skipWhitespace()
                value = readAttributeValue()
            }
            if attributes[attrName] == nil { attributes[attrName] = HTMLEntities.decode(value) }
        }
        if !selfClosing, name == "script" || name == "style" || name == "title" {
            pendingRawTextEnd = name
        }
        return .start(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    private mutating func readName() -> String {
        var out = String.UnicodeScalarView()
        while i < s.count {
            let c = s[i]
            if c == ">" || c == "/" || c == "=" || c.properties.isWhitespace { break }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    private mutating func readAttributeValue() -> String {
        guard i < s.count else { return "" }
        var out = String.UnicodeScalarView()
        let quote = s[i]
        if quote == "\"" || quote == "'" {
            i += 1
            while i < s.count, s[i] != quote { out.append(s[i]); i += 1 }
            i = min(s.count, i + 1)
        } else {
            while i < s.count, s[i] != ">", !s[i].properties.isWhitespace { out.append(s[i]); i += 1 }
        }
        return String(out)
    }

    private mutating func skipRawText(until name: String) {
        let closing = Array("</\(name)".unicodeScalars)
        while i < s.count {
            if s[i] == "<", matches(closing, caseInsensitive: true) {
                skip(past: ">")
                return
            }
            i += 1
        }
    }

    private mutating func skipWhitespace() {
        while i < s.count, s[i].properties.isWhitespace { i += 1 }
    }

    private mutating func skip(past marker: String) {
        let m = Array(marker.unicodeScalars)
        while i < s.count {
            if matches(m, caseInsensitive: false) { i += m.count; return }
            i += 1
        }
    }

    private func starts(with marker: String) -> Bool {
        matches(Array(marker.unicodeScalars), caseInsensitive: true)
    }

    private func matches(_ m: [Unicode.Scalar], caseInsensitive: Bool) -> Bool {
        guard i + m.count <= s.count else { return false }
        for k in 0..<m.count {
            let a = s[i + k], b = m[k]
            if a == b { continue }
            if caseInsensitive, String(a).lowercased() == String(b).lowercased() { continue }
            return false
        }
        return true
    }

    static func localName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if let colon = lower.lastIndex(of: ":") { return String(lower[lower.index(after: colon)...]) }
        return lower
    }
}

// MARK: - Entities

enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "shy": "\u{00AD}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "zwj": "\u{200D}", "zwnj": "\u{200C}",
        "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
        "ldquo": "“", "rdquo": "”", "bdquo": "„", "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶", "middot": "·", "bull": "•",
        "deg": "°", "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "pound": "£", "euro": "€", "yen": "¥", "cent": "¢", "dagger": "†", "Dagger": "‡", "prime": "′",
        "iexcl": "¡", "iquest": "¿",
        "aacute": "á", "eacute": "é", "iacute": "í", "oacute": "ó", "uacute": "ú", "yacute": "ý",
        "Aacute": "Á", "Eacute": "É", "Iacute": "Í", "Oacute": "Ó", "Uacute": "Ú",
        "agrave": "à", "egrave": "è", "igrave": "ì", "ograve": "ò", "ugrave": "ù",
        "Agrave": "À", "Egrave": "È",
        "acirc": "â", "ecirc": "ê", "icirc": "î", "ocirc": "ô", "ucirc": "û",
        "auml": "ä", "euml": "ë", "iuml": "ï", "ouml": "ö", "uuml": "ü", "yuml": "ÿ",
        "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "atilde": "ã", "ntilde": "ñ", "otilde": "õ", "Ntilde": "Ñ",
        "ccedil": "ç", "Ccedil": "Ç", "aring": "å", "Aring": "Å", "aelig": "æ", "AElig": "Æ",
        "oslash": "ø", "Oslash": "Ø", "oelig": "œ", "OElig": "Œ",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            guard c == "&" else {
                out.append(c)
                index = text.index(after: index)
                continue
            }
            // Find ";" within a short window.
            var end = text.index(after: index)
            var length = 0
            while end < text.endIndex, text[end] != ";", text[end] != "&", length < 12 {
                end = text.index(after: end)
                length += 1
            }
            if end < text.endIndex, text[end] == ";" {
                let name = String(text[text.index(after: index)..<end])
                if let decoded = decodeEntity(name) {
                    out += decoded
                    index = text.index(after: end)
                    continue
                }
            }
            out.append("&")
            index = text.index(after: index)
        }
        return out
    }

    static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value: UInt32?
            if digits.first == "x" || digits.first == "X" {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[name]
    }
}

// MARK: - Block builder

private struct BlockBuilder {
    let resolveURL: (String) -> URL?
    private(set) var blocks: [BookBlock] = []

    private var runs: [TextRun] = []
    private var lastWasSpace = true
    private var pendingAnchor: String?

    private struct InlineEntry { var name: String; var style: TextRun.Style }
    private var inline: [InlineEntry] = []
    private var style: TextRun.Style { inline.reduce([]) { $0.union($1.style) } }

    private struct AlignEntry { var name: String; var alignment: BlockAlignment }
    private var alignStack: [AlignEntry] = []
    private var alignment: BlockAlignment {
        alignStack.last(where: { $0.alignment != .natural })?.alignment ?? .natural
    }

    private var heading: Int?
    private var quoteDepth = 0
    private var preDepth = 0
    private var preText = ""
    private struct ListEntry { var ordered: Bool; var counter: Int }
    private var lists: [ListEntry] = []
    private var pendingMarker: String?
    private var svgDepth = 0
    private var skipDepth = 0

    init(resolveURL: @escaping (String) -> URL?) {
        self.resolveURL = resolveURL
    }

    static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "aside", "nav", "figure",
        "figcaption", "center", "body", "html", "table", "thead", "tbody", "tfoot", "tr", "caption",
        "dl", "dt", "dd", "address", "details", "summary", "hgroup", "fieldset",
    ]
    static let skipTags: Set<String> = ["head", "script", "style", "title", "noscript", "button", "select", "textarea", "template"]
    static let voidTags: Set<String> = ["br", "img", "hr", "meta", "link", "input", "wbr", "col", "area", "base", "source", "image"]

    static func inlineStyle(for name: String, attributes: [String: String]) -> TextRun.Style? {
        var style: TextRun.Style
        switch name {
        case "b", "strong": style = .bold
        case "i", "em", "cite", "dfn", "var": style = .italic
        case "code", "tt", "kbd", "samp": style = .monospace
        case "sup": style = .raised
        case "sub": style = .lowered
        case "u", "ins": style = .underline
        case "s", "strike", "del": style = .strikethrough
        case "span", "a", "small", "big", "font", "abbr", "acronym", "q", "mark", "time", "bdi", "bdo", "label":
            style = []
        default: return nil
        }
        let css = (attributes["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        if css.contains("font-weight:bold") || css.contains("font-weight:700") || css.contains("font-weight:600")
            || css.contains("font-weight:800") || css.contains("font-weight:900") {
            style.insert(.bold)
        }
        if css.contains("font-style:italic") || css.contains("font-style:oblique") { style.insert(.italic) }
        if css.contains("font-variant:small-caps") { style.insert(.smallCaps) }
        if css.contains("text-decoration:underline") { style.insert(.underline) }
        let cls = (attributes["class"] ?? "").lowercased()
        if cls.split(separator: " ").contains(where: { $0 == "italic" || $0 == "ital" || $0 == "em" }) { style.insert(.italic) }
        if cls.split(separator: " ").contains(where: { $0 == "bold" || $0 == "strong" }) { style.insert(.bold) }
        if cls.contains("smallcap") || cls.contains("small-cap") { style.insert(.smallCaps) }
        return style
    }

    static func alignment(_ attributes: [String: String]) -> BlockAlignment {
        let align = (attributes["align"] ?? "").lowercased()
        let css = (attributes["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        let classes = (attributes["class"] ?? "").lowercased().split(separator: " ")
        let centeredClass = classes.contains { $0.contains("center") || $0.contains("centre") }
        let rightClass = classes.contains { ["right", "align-right", "right-align", "text-right", "rtext"].contains(String($0)) }
        if align == "center" || css.contains("text-align:center") || centeredClass { return .center }
        if align == "right" || css.contains("text-align:right") || rightClass { return .right }
        return .natural
    }

    mutating func handle(_ token: HTMLToken) {
        switch token {
        case .text(let text):
            guard skipDepth == 0, svgDepth == 0 else { return }
            appendText(text)
        case .start(let name, let attributes, let selfClosing):
            start(name, attributes, selfClosing: selfClosing)
        case .end(let name):
            end(name)
        }
    }

    private mutating func start(_ name: String, _ attributes: [String: String], selfClosing: Bool) {
        if Self.skipTags.contains(name) {
            // The tokenizer already swallowed script/style/title bodies.
            if !selfClosing, name != "script", name != "style", name != "title" { skipDepth += 1 }
            return
        }
        guard skipDepth == 0 else { return }
        // Set after the switch, which may first end the previous block.
        defer {
            if let id = attributes["id"], !id.isEmpty, pendingAnchor == nil { pendingAnchor = id }
        }

        if name == "svg" {
            if !selfClosing { svgDepth += 1 }
            return
        }
        if name == "img" || name == "image" {
            let src = attributes["src"] ?? attributes["xlink:href"] ?? attributes["href"] ?? ""
            if !src.isEmpty, !src.hasPrefix("data:"), let url = resolveURL(src) {
                flush()
                let alt = attributes["alt"].flatMap { $0.isEmpty ? nil : $0 }
                blocks.append(.image(url: url, alt: alt))
            }
            return
        }
        guard svgDepth == 0 else { return }

        if preDepth > 0, name != "pre" {
            if name == "br" { preText += "\n" }
            return
        }

        switch name {
        case "br":
            appendBreak()
        case "hr":
            flush()
            blocks.append(.rule)
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flush()
            heading = Int(name.dropFirst()) ?? 1
            pushAlign(name, attributes)
        case "blockquote":
            flush()
            quoteDepth += 1
            pushAlign(name, attributes)
        case "pre":
            flush()
            preDepth += 1
        case "ul", "ol":
            flush()
            let start = Int(attributes["start"] ?? "") ?? 1
            lists.append(ListEntry(ordered: name == "ol", counter: start))
        case "li":
            flush()
            if lists.isEmpty { lists.append(ListEntry(ordered: false, counter: 1)) }
            let top = lists[lists.count - 1]
            pendingMarker = top.ordered ? "\(top.counter)." : "•"
            lists[lists.count - 1].counter += 1
        case "td", "th":
            if !runs.isEmpty { appendText(" ") }
            if let s = Self.inlineStyle(for: name == "th" ? "b" : "span", attributes: attributes), !selfClosing {
                inline.append(InlineEntry(name: name, style: s))
            }
        default:
            if Self.blockTags.contains(name) {
                flush()
                if !selfClosing { pushAlign(name, attributes) }
            } else if let s = Self.inlineStyle(for: name, attributes: attributes), !selfClosing {
                inline.append(InlineEntry(name: name, style: s))
            }
        }
    }

    private mutating func end(_ name: String) {
        if Self.skipTags.contains(name) {
            if name != "script", name != "style", name != "title" { skipDepth = max(0, skipDepth - 1) }
            return
        }
        guard skipDepth == 0 else { return }
        if name == "svg" { svgDepth = max(0, svgDepth - 1); return }
        guard svgDepth == 0 else { return }

        switch name {
        case "pre":
            if preDepth > 0 {
                preDepth -= 1
                if preDepth == 0 {
                    var text = preText
                    if text.hasPrefix("\n") { text.removeFirst() }
                    while text.hasSuffix("\n") { text.removeLast() }
                    if !text.isEmpty { blocks.append(.preformatted(text)) }
                    preText = ""
                }
            }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flush()
            heading = nil
            popAlign(name)
        case "blockquote":
            flush()
            quoteDepth = max(0, quoteDepth - 1)
            popAlign(name)
        case "ul", "ol":
            flush()
            if !lists.isEmpty { lists.removeLast() }
        case "li":
            flush()
            pendingMarker = nil
        case "td", "th":
            popInline(name)
        default:
            if Self.blockTags.contains(name) {
                flush()
                popAlign(name)
            } else {
                popInline(name)
            }
        }
    }

    private mutating func pushAlign(_ name: String, _ attributes: [String: String]) {
        alignStack.append(AlignEntry(name: name, alignment: Self.alignment(attributes)))
    }

    private mutating func popAlign(_ name: String) {
        if let i = alignStack.lastIndex(where: { $0.name == name }) { alignStack.removeSubrange(i...) }
    }

    private mutating func popInline(_ name: String) {
        if let i = inline.lastIndex(where: { $0.name == name }) { inline.remove(at: i) }
    }

    private mutating func appendText(_ text: String) {
        if preDepth > 0 {
            preText += text
            return
        }
        var out = ""
        for ch in text {
            if ch.isWhitespace, ch != "\u{00A0}" {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else if ch == "\u{00AD}" {
                // Soft hyphen: let the layout hyphenate instead.
                continue
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        append(out)
    }

    private mutating func appendBreak() {
        // Drop a trailing space before the break.
        if var last = runs.last, last.text.hasSuffix(" ") {
            last.text.removeLast()
            runs[runs.count - 1] = last
        }
        guard !runs.isEmpty else { return }
        append("\n")
        lastWasSpace = true
    }

    private mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        let style = self.style
        if var last = runs.last, last.style == style {
            last.text += text
            runs[runs.count - 1] = last
        } else {
            runs.append(TextRun(text, style: style))
        }
    }

    /// Ends the block being built, if it has any text.
    private mutating func flush() {
        defer {
            runs = []
            lastWasSpace = true
        }
        // Trim trailing whitespace and line breaks.
        while var last = runs.last {
            while let c = last.text.last, c == " " || c == "\n" { last.text.removeLast() }
            if last.text.isEmpty { runs.removeLast() } else { runs[runs.count - 1] = last; break }
        }
        // Trim leading line breaks.
        while var first = runs.first {
            while let c = first.text.first, c == " " || c == "\n" { first.text.removeFirst() }
            if first.text.isEmpty { runs.removeFirst() } else { runs[0] = first; break }
        }
        guard !runs.isEmpty else { return }
        let anchor = pendingAnchor
        pendingAnchor = nil
        if let level = heading {
            blocks.append(.heading(level: level, runs: runs, anchor: anchor))
        } else if !lists.isEmpty, let marker = pendingMarker {
            blocks.append(.listItem(marker: marker, depth: lists.count, runs: runs))
            pendingMarker = ""
        } else if quoteDepth > 0 {
            blocks.append(.quote(runs: runs, anchor: anchor))
        } else {
            blocks.append(.paragraph(runs: runs, alignment: alignment, anchor: anchor))
        }
    }

    mutating func finish() {
        if preDepth > 0, !preText.isEmpty { blocks.append(.preformatted(preText)); preText = "" }
        flush()
    }
}
