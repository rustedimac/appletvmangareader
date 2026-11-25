import Foundation

/// Numeric-aware, locale-aware ordering for series titles, chapter names,
/// page and file names: "Chapter 2" comes before "Chapter 10", "10.5" sits
/// between 10 and 11, and "第二話" before "第十話".
///
/// How two names compare:
/// - Each name is split into runs of digits and runs of text. Spaces,
///   punctuation and symbols (including `[]`, `()`, `【】`, `「」`, `-`, `_`)
///   only separate runs, so "Ch.2", "Ch 2" and "Ch_2" sort together.
/// - Digit runs compare by value, with any length (no overflow) and any
///   Unicode decimal digits (full-width `１２`, Arabic-Indic, …). A run with
///   a decimal point ("10.5") keeps its fraction. Kanji numerals
///   (`〇一二三四五六七八九十百千`) are read as numbers too, both "二十三"
///   and "二〇二三" styles.
/// - Text runs compare with the locale's collation, ignoring case, accents
///   and full/half width.
/// - A number sorts before text at the same position, and a name that is a
///   prefix of another comes first ("Volume" before "Volume 2").
/// - Names that still tie are ordered by their exact characters, so the
///   order is always total and stable across runs.
public enum NaturalSort {
    public struct Options: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Skips bracketed tags without digits, such as "[Scanlator]",
        /// "(Digital)" or "【完結】", so tags don't decide the order. Tags with
        /// digits ("[01]", "(2019)") are kept. If nothing but tags is left the
        /// whole name is used.
        public static let ignoringBracketedTags = Options(rawValue: 1 << 0)
        /// Skips a short trailing file extension (".cbz", ".jpg", ".webp").
        public static let ignoringExtension = Options(rawValue: 1 << 1)

        /// For file and archive-entry names.
        public static let fileName: Options = [.ignoringBracketedTags, .ignoringExtension]
    }

    /// Orders `a` and `b`. `locale` nil compares text without a locale
    /// (Unicode order), which is what tests use for repeatable results.
    public static func compare(_ a: String, _ b: String, options: Options = [],
                               locale: Locale? = .current) -> ComparisonResult {
        Key(a, options: options, locale: locale).compare(to: Key(b, options: options, locale: locale))
    }

    /// `compare(a, b) == .orderedAscending`, for `sorted(by:)`.
    public static func areInIncreasingOrder(_ a: String, _ b: String, options: Options = [],
                                            locale: Locale? = .current) -> Bool {
        compare(a, b, options: options, locale: locale) == .orderedAscending
    }

    /// A name split once into comparable runs. Sorting with keys avoids
    /// re-splitting names on every comparison.
    public struct Key: Comparable, Sendable {
        public let original: String
        let tokens: [Token]
        let locale: Locale?

        public init(_ string: String, options: Options = [], locale: Locale? = .current) {
            original = string
            self.locale = locale
            var source = string
            if options.contains(.ignoringExtension) { source = NaturalSort.droppingExtension(source) }
            if options.contains(.ignoringBracketedTags) {
                let stripped = NaturalSort.droppingTags(source)
                let stripTokens = NaturalSort.tokenize(stripped)
                tokens = stripTokens.isEmpty ? NaturalSort.tokenize(source) : stripTokens
            } else {
                tokens = NaturalSort.tokenize(source)
            }
        }

        public func compare(to other: Key) -> ComparisonResult {
            for (a, b) in zip(tokens, other.tokens) {
                let r = a.compare(to: b, locale: locale)
                if r != .orderedSame { return r }
            }
            if tokens.count != other.tokens.count {
                return tokens.count < other.tokens.count ? .orderedAscending : .orderedDescending
            }
            if original == other.original { return .orderedSame }
            // Ties ("Ch 1" vs "ch-01"): case-insensitive first, then exact
            // characters, so the result never depends on input order.
            let folded = original.compare(other.original, options: [.caseInsensitive, .widthInsensitive])
            if folded != .orderedSame { return folded }
            return original < other.original ? .orderedAscending : .orderedDescending
        }

        public static func < (lhs: Key, rhs: Key) -> Bool { lhs.compare(to: rhs) == .orderedAscending }
        public static func == (lhs: Key, rhs: Key) -> Bool { lhs.compare(to: rhs) == .orderedSame }
    }

    // MARK: Tokens

    enum Token: Sendable, Equatable {
        case number(NumberValue)
        case text(String)

        func compare(to other: Token, locale: Locale?) -> ComparisonResult {
            switch (self, other) {
            case (.number(let a), .number(let b)):
                return a.compare(to: b)
            case (.number, .text):
                return .orderedAscending
            case (.text, .number):
                return .orderedDescending
            case (.text(let a), .text(let b)):
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
                return a.compare(b, options: options, range: nil, locale: locale)
            }
        }
    }

    /// A non-negative decimal number held as digits, so any length compares
    /// correctly. `integer` has no leading zeros; `fraction` no trailing ones.
    struct NumberValue: Sendable, Equatable {
        var integer: [UInt8]
        var fraction: [UInt8]

        init(integer: [UInt8], fraction: [UInt8] = []) {
            var f = fraction
            while f.last == 0 { f.removeLast() }
            self.integer = Array(integer.drop(while: { $0 == 0 }))
            self.fraction = f
        }

        init(_ value: Int) {
            self.init(integer: String(max(0, value)).compactMap { $0.wholeNumberValue.map(UInt8.init) })
        }

        func compare(to other: NumberValue) -> ComparisonResult {
            if integer.count != other.integer.count {
                return integer.count < other.integer.count ? .orderedAscending : .orderedDescending
            }
            for (a, b) in zip(integer, other.integer) where a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
            for (a, b) in zip(fraction, other.fraction) where a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
            if fraction.count != other.fraction.count {
                return fraction.count < other.fraction.count ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        }
    }

    static func tokenize(_ string: String) -> [Token] {
        let chars = Array(string)
        var tokens: [Token] = []
        var text = ""
        var i = 0

        func flushText() {
            if !text.isEmpty { tokens.append(.text(text)); text = "" }
        }

        while i < chars.count {
            let c = chars[i]
            if let d = decimalDigit(c) {
                flushText()
                var integer: [UInt8] = [d]
                i += 1
                while i < chars.count, let d = decimalDigit(chars[i]) { integer.append(d); i += 1 }
                var fraction: [UInt8] = []
                if i + 1 < chars.count, isDecimalPoint(chars[i]), decimalDigit(chars[i + 1]) != nil {
                    i += 1
                    while i < chars.count, let d = decimalDigit(chars[i]) { fraction.append(d); i += 1 }
                }
                tokens.append(.number(NumberValue(integer: integer, fraction: fraction)))
            } else if kanjiValue(c) != nil {
                flushText()
                var run: [Character] = []
                while i < chars.count, kanjiValue(chars[i]) != nil { run.append(chars[i]); i += 1 }
                if let value = kanjiNumber(run) {
                    tokens.append(.number(NumberValue(value)))
                } else {
                    text.append(contentsOf: run)
                }
            } else if isSeparator(c) {
                flushText()
                i += 1
            } else {
                text.append(c)
                i += 1
            }
        }
        flushText()
        return tokens
    }

    /// 0–9 for any Unicode decimal digit (not ①, Ⅻ or ½).
    static func decimalDigit(_ c: Character) -> UInt8? {
        guard c.unicodeScalars.count == 1, let scalar = c.unicodeScalars.first,
              scalar.properties.numericType == .decimal,
              let value = c.wholeNumberValue, (0...9).contains(value) else { return nil }
        return UInt8(value)
    }

    static func isDecimalPoint(_ c: Character) -> Bool { c == "." || c == "．" }

    static func isSeparator(_ c: Character) -> Bool {
        c.isWhitespace || c.isPunctuation || c.isSymbol
    }

    private static let kanjiDigits: [Character: Int] = [
        "〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let kanjiMultipliers: [Character: Int] = ["十": 10, "百": 100, "千": 1000]

    static func kanjiValue(_ c: Character) -> Int? { kanjiDigits[c] ?? kanjiMultipliers[c] }

    /// Reads "二十三" (23), "百二" (102), "二〇二三" (2023). Nil if the run is
    /// too long to be a sensible number.
    static func kanjiNumber(_ run: [Character]) -> Int? {
        guard !run.isEmpty, run.count <= 12 else { return nil }
        var total = 0
        var current = 0
        for c in run {
            if let d = kanjiDigits[c] {
                current = current * 10 + d
            } else if let m = kanjiMultipliers[c] {
                total += max(current, 1) * m
                current = 0
            }
        }
        return total + current
    }

    /// "Vol 01.cbz" → "Vol 01". Only short alphanumeric extensions that
    /// don't start with a digit, so "Chapter 10.5" keeps its fraction.
    static func droppingExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        let ext = name[name.index(after: dot)...]
        guard (1...5).contains(ext.count), let first = ext.first, first.isLetter,
              ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return name }
        return String(name[..<dot])
    }

    private static let tagPairs: [Character: Character] = [
        "[": "]", "(": ")", "{": "}", "【": "】", "（": "）", "［": "］", "〔": "〕", "「": "」", "『": "』",
    ]

    /// Removes bracketed tags that contain no digits. Unbalanced brackets
    /// are left as they are.
    static func droppingTags(_ name: String) -> String {
        var result = ""
        var i = name.startIndex
        while i < name.endIndex {
            let c = name[i]
            if let close = tagPairs[c], let end = name[name.index(after: i)...].firstIndex(of: close) {
                let inner = name[name.index(after: i)..<end]
                if inner.contains(where: { decimalDigit($0) != nil }) {
                    result.append(contentsOf: name[i...end])
                } else {
                    result.append(" ")
                }
                i = name.index(after: end)
            } else {
                result.append(c)
                i = name.index(after: i)
            }
        }
        return result
    }
}

public extension Sequence {
    /// Sorted by `name` with `NaturalSort`. Stable for equal names.
    func naturallySorted(by name: (Element) -> String, options: NaturalSort.Options = [],
                         locale: Locale? = .current) -> [Element] {
        enumerated()
            .map { (key: NaturalSort.Key(name($0.element), options: options, locale: locale), offset: $0.offset, element: $0.element) }
            .sorted { a, b in
                let r = a.key.compare(to: b.key)
                return r == .orderedSame ? a.offset < b.offset : r == .orderedAscending
            }
            .map { $0.element }
    }
}

public extension Sequence where Element == String {
    /// Names in natural order.
    func naturallySorted(options: NaturalSort.Options = [], locale: Locale? = .current) -> [String] {
        naturallySorted(by: { $0 }, options: options, locale: locale)
    }
}
