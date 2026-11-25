import Foundation

public enum BookTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case dark
    case sepia
    case light

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum BookFont: String, Codable, CaseIterable, Sendable, Identifiable {
    case serif
    case sans

    public var id: String { rawValue }
    public var title: String { self == .serif ? "Serif" : "Sans Serif" }
}

public enum BookLineSpacing: String, Codable, CaseIterable, Sendable, Identifiable {
    case compact
    case normal
    case relaxed

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    /// Line height as a multiple of the font size.
    public var multiple: Double {
        switch self {
        case .compact: return 1.15
        case .normal: return 1.35
        case .relaxed: return 1.6
        }
    }
}

/// Book reader settings. Saved per profile, not per book, the way Kindle
/// and Apple Books work: people pick a comfortable size and theme once.
public struct BookSettings: Codable, Hashable, Sendable {
    /// Body text size in points. One of `fontSizes`.
    public var fontSize: Double
    public var font: BookFont
    public var lineSpacing: BookLineSpacing
    public var theme: BookTheme
    /// One column, or two side by side like an open book.
    public var columns: Int
    public var justified: Bool

    /// Sizes the menu steps through. TV text is read from across a room,
    /// so the smallest is still large.
    public static let fontSizes: [Double] = [26, 30, 34, 38, 44, 50, 58]

    public init(fontSize: Double = 34, font: BookFont = .serif, lineSpacing: BookLineSpacing = .normal,
                theme: BookTheme = .dark, columns: Int = 2, justified: Bool = true) {
        self.fontSize = fontSize
        self.font = font
        self.lineSpacing = lineSpacing
        self.theme = theme
        self.columns = columns
        self.justified = justified
    }

    public static let `default` = BookSettings()

    public var clampedColumns: Int { columns >= 2 ? 2 : 1 }

    /// Index of the current size in `fontSizes` (nearest).
    public var fontSizeIndex: Int {
        Self.fontSizes.indices.min { abs(Self.fontSizes[$0] - fontSize) < abs(Self.fontSizes[$1] - fontSize) } ?? 2
    }

    public var canGrow: Bool { fontSizeIndex < Self.fontSizes.count - 1 }
    public var canShrink: Bool { fontSizeIndex > 0 }

    public func larger() -> BookSettings {
        var s = self
        s.fontSize = Self.fontSizes[min(Self.fontSizes.count - 1, fontSizeIndex + 1)]
        return s
    }

    public func smaller() -> BookSettings {
        var s = self
        s.fontSize = Self.fontSizes[max(0, fontSizeIndex - 1)]
        return s
    }

    enum CodingKeys: String, CodingKey { case fontSize, font, lineSpacing, theme, columns, justified }

    /// Missing or unknown values fall back to defaults, so adding a setting
    /// never loses the others.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BookSettings.default
        fontSize = (try? c.decodeIfPresent(Double.self, forKey: .fontSize)) ?? d.fontSize
        font = (try? c.decodeIfPresent(BookFont.self, forKey: .font)) ?? d.font
        lineSpacing = (try? c.decodeIfPresent(BookLineSpacing.self, forKey: .lineSpacing)) ?? d.lineSpacing
        theme = (try? c.decodeIfPresent(BookTheme.self, forKey: .theme)) ?? d.theme
        columns = (try? c.decodeIfPresent(Int.self, forKey: .columns)) ?? d.columns
        justified = (try? c.decodeIfPresent(Bool.self, forKey: .justified)) ?? d.justified
    }
}
