import Foundation

public enum ReadingMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Page turner. Shows one or two pages depending on `PageLayout`.
    case paged
    /// Continuous vertical scroll with pages joined edge to edge.
    case webtoon

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .paged: return "Paged"
        case .webtoon: return "Vertical Scroll"
        }
    }
}

public enum ReadingDirection: String, Codable, CaseIterable, Sendable, Identifiable {
    case leftToRight
    case rightToLeft

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .leftToRight: return "Left to Right"
        case .rightToLeft: return "Right to Left"
        }
    }
}

public enum PageLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    case single
    case double

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .single: return "Single Page"
        case .double: return "Two Pages"
        }
    }
}

public enum ReaderBackground: String, Codable, CaseIterable, Sendable, Identifiable {
    case black
    case gray
    case white

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Reader configuration. Profiles have a default; each series can override
/// it (changes made from the in-reader menu are saved per series, the way
/// Mihon and Kavita do it).
public struct ReaderSettings: Codable, Hashable, Sendable {
    public var mode: ReadingMode
    public var direction: ReadingDirection
    public var layout: PageLayout
    /// Show the chapter's first page alone (cover / right-hand first page).
    public var firstPageAlone: Bool
    /// Flip spread pairing by one page, for when pairs come out wrong.
    public var shiftPairing: Bool
    public var background: ReaderBackground
    /// Webtoon column width as a fraction of screen width (0.3...1.0).
    public var webtoonWidth: Double
    /// Points scrolled per remote press in webtoon mode, as a fraction of
    /// screen height.
    public var webtoonScrollStep: Double

    public init(mode: ReadingMode = .paged,
                direction: ReadingDirection = .rightToLeft,
                layout: PageLayout = .double,
                firstPageAlone: Bool = true,
                shiftPairing: Bool = false,
                background: ReaderBackground = .black,
                webtoonWidth: Double = 0.6,
                webtoonScrollStep: Double = 0.75) {
        self.mode = mode
        self.direction = direction
        self.layout = layout
        self.firstPageAlone = firstPageAlone
        self.shiftPairing = shiftPairing
        self.background = background
        self.webtoonWidth = webtoonWidth
        self.webtoonScrollStep = webtoonScrollStep
    }

    public static let `default` = ReaderSettings()

    /// Default for webtoon-style series (long strips).
    public static let webtoonDefault = ReaderSettings(mode: .webtoon, direction: .leftToRight, layout: .single)

    public var clampedWebtoonWidth: Double { min(1.0, max(0.3, webtoonWidth)) }

    /// Spreads for a chapter under these settings.
    public func layout(for sizes: [PageSize?]) -> SpreadLayout {
        switch (mode, layout) {
        case (.paged, .double):
            return SpreadLayout(sizes: sizes, firstPageAlone: firstPageAlone, shift: shiftPairing)
        default:
            return .singles(pageCount: sizes.count)
        }
    }
}
