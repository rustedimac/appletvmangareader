import Foundation

/// One setting row in the in-reader menu.
public enum ReaderMenuItem: String, CaseIterable, Sendable, Identifiable {
    case mode
    case layout
    case direction
    case firstPageAlone
    case shiftPairing
    case background
    case webtoonWidth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mode: return "Reading Mode"
        case .layout: return "Page Layout"
        case .direction: return "Direction"
        case .firstPageAlone: return "First Page Alone"
        case .shiftPairing: return "Page Pairing"
        case .background: return "Background"
        case .webtoonWidth: return "Column Width"
        }
    }
}

/// What the in-reader menu shows for a given set of settings, and the small
/// rules behind each control. Kept out of the UI so it can be unit tested.
public enum ReaderMenuOptions {
    /// Rows that apply to the current settings, top to bottom. Options that
    /// can't affect what's on screen are hidden (pairing in single-page
    /// layout, column width in paged mode, and so on), the way Mihon swaps
    /// its reading-mode sheet per mode.
    public static func items(for settings: ReaderSettings) -> [ReaderMenuItem] {
        switch settings.mode {
        case .paged:
            var items: [ReaderMenuItem] = [.mode, .layout, .direction]
            if settings.layout == .double { items += [.firstPageAlone, .shiftPairing] }
            items.append(.background)
            return items
        case .webtoon:
            return [.mode, .webtoonWidth, .background]
        }
    }

    /// Column width steps for the webtoon reader, as a fraction of screen width.
    public static let webtoonWidths: [Double] = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

    /// The width step closest to `width`.
    public static func nearestWidthIndex(_ width: Double) -> Int {
        var best = 0
        for (i, w) in webtoonWidths.enumerated() where abs(w - width) < abs(webtoonWidths[best] - width) {
            best = i
        }
        return best
    }

    /// Moves the webtoon width by `steps` presets, clamped to the range.
    public static func steppedWidth(_ width: Double, by steps: Int) -> Double {
        let i = min(webtoonWidths.count - 1, max(0, nearestWidthIndex(width) + steps))
        return webtoonWidths[i]
    }

    public static func canStepWidth(_ width: Double, by steps: Int) -> Bool {
        steppedWidth(width, by: steps) != webtoonWidths[nearestWidthIndex(width)]
    }

    /// "60%".
    public static func widthLabel(_ width: Double) -> String {
        "\(Int((webtoonWidths[nearestWidthIndex(width)] * 100).rounded()))%"
    }

    /// The page position line in the menu header, e.g. "Pages 2–3 of 20".
    public static func positionLabel(visiblePages: [Int], pageCount: Int) -> String {
        guard pageCount > 0, let first = visiblePages.first else { return "" }
        if visiblePages.count > 1, let last = visiblePages.last {
            return "Pages \(first + 1)–\(last + 1) of \(pageCount)"
        }
        return "Page \(first + 1) of \(pageCount)"
    }
}

public extension ReaderSettings {
    /// A copy with one field changed: `settings.with(\.layout, .single)`.
    func with<Value>(_ keyPath: WritableKeyPath<ReaderSettings, Value>, _ value: Value) -> ReaderSettings {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}
