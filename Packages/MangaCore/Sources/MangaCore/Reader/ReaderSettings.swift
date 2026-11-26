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
    /// Single-page paged layout: show a wide page (a scanned two-page
    /// spread) as two screens, one half at a time, in reading order.
    public var splitWidePages: Bool
    /// Brightness, contrast, color mode, sharpening and upscaling.
    public var picture: PictureSettings

    public init(mode: ReadingMode = .paged,
                direction: ReadingDirection = .rightToLeft,
                layout: PageLayout = .double,
                firstPageAlone: Bool = true,
                shiftPairing: Bool = false,
                background: ReaderBackground = .black,
                webtoonWidth: Double = 0.6,
                webtoonScrollStep: Double = 0.75,
                splitWidePages: Bool = false,
                picture: PictureSettings = .default) {
        self.mode = mode
        self.direction = direction
        self.layout = layout
        self.firstPageAlone = firstPageAlone
        self.shiftPairing = shiftPairing
        self.background = background
        self.webtoonWidth = webtoonWidth
        self.webtoonScrollStep = webtoonScrollStep
        self.splitWidePages = splitWidePages
        self.picture = picture
    }

    private enum CodingKeys: String, CodingKey {
        case mode, direction, layout, firstPageAlone, shiftPairing, background
        case webtoonWidth, webtoonScrollStep, splitWidePages, picture
    }

    /// Missing or unknown values fall back to the defaults, so settings
    /// saved (or synced) by an older build without the newer fields still
    /// load instead of being thrown away.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        mode = value(.mode, d.mode)
        direction = value(.direction, d.direction)
        layout = value(.layout, d.layout)
        firstPageAlone = value(.firstPageAlone, d.firstPageAlone)
        shiftPairing = value(.shiftPairing, d.shiftPairing)
        background = value(.background, d.background)
        webtoonWidth = value(.webtoonWidth, d.webtoonWidth)
        webtoonScrollStep = value(.webtoonScrollStep, d.webtoonScrollStep)
        splitWidePages = value(.splitWidePages, d.splitWidePages)
        picture = value(.picture, d.picture)
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
        case (.paged, .single) where splitWidePages:
            return .singles(splitting: sizes, direction: direction)
        default:
            return .singles(pageCount: sizes.count)
        }
    }
}
