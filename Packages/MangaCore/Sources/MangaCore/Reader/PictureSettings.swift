import Foundation

/// How page colors are drawn.
public enum PictureColorMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case normal
    /// Color pages in black and white.
    case grayscale
    /// Night mode: white paper turns black and black ink turns white (in
    /// black and white, since inverted color art looks wrong).
    case inverted

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .grayscale: return "Grayscale"
        case .inverted: return "Night (Invert)"
        }
    }
}

/// Extra sharpening after a page is scaled to the screen.
public enum PictureSharpen: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case low
    case high

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .high: return "High"
        }
    }

    /// `CISharpenLuminance` sharpness.
    public var amount: Double {
        switch self {
        case .off: return 0
        case .low: return 0.4
        case .high: return 0.9
        }
    }
}

/// How pages smaller than the screen are enlarged.
public enum PictureUpscaling: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The system's GPU filtering (fast, a little soft).
    case standard
    /// Lanczos resampling with Core Image (Metal), for low-resolution scans
    /// on a 4K screen. Sharper edges on line art.
    case lanczos

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .lanczos: return "Sharp (Lanczos)"
        }
    }
}

/// Picture controls for image pages: brightness, contrast, color mode,
/// sharpening and upscaling. Part of `ReaderSettings`, so they save per
/// series (or as the profile default) and sync with the other reader
/// settings.
///
/// Brightness, contrast and color apply in both readers as live view
/// effects. Sharpening and Lanczos upscaling re-render the page image, so
/// they're offered in the paged reader only.
public struct PictureSettings: Codable, Hashable, Sendable {
    /// Added to every color channel: -0.5 (much darker) ... 0.3 (brighter).
    public var brightness: Double
    /// Contrast multiplier: 0.6 (flat) ... 1.5 (punchy). 1 is unchanged.
    public var contrast: Double
    public var color: PictureColorMode
    public var sharpen: PictureSharpen
    public var upscaling: PictureUpscaling

    public init(brightness: Double = 0, contrast: Double = 1, color: PictureColorMode = .normal,
                sharpen: PictureSharpen = .off, upscaling: PictureUpscaling = .standard) {
        self.brightness = brightness
        self.contrast = contrast
        self.color = color
        self.sharpen = sharpen
        self.upscaling = upscaling
    }

    public static let `default` = PictureSettings()

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, color, sharpen, upscaling
    }

    /// Missing or unknown values fall back to the defaults, so a newer
    /// build's settings (or an older build's) always load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PictureSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        brightness = value(.brightness, d.brightness)
        contrast = value(.contrast, d.contrast)
        color = value(.color, d.color)
        sharpen = value(.sharpen, d.sharpen)
        upscaling = value(.upscaling, d.upscaling)
    }

    // MARK: Steps for the menu

    public static let brightnessSteps: [Double] = [-0.5, -0.4, -0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3]
    public static let contrastSteps: [Double] = [0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5]

    public var clampedBrightness: Double { min(0.3, max(-0.5, brightness)) }
    public var clampedContrast: Double { min(1.5, max(0.6, contrast)) }

    /// True when nothing changes how pages look.
    public var isDefault: Bool { self == .default }

    /// Sharpening or Lanczos upscaling is on, so page images are re-rendered.
    public var needsProcessing: Bool { sharpen != .off || upscaling == .lanczos }

    /// Whether Lanczos should enlarge an image decoded at `decoded` pixels
    /// to fill `frame` pixels. Only for real enlargement (over 5 %), so
    /// pages that already fill the screen are left alone.
    public func shouldUpscale(decoded: PageSize, toFill frame: PageSize) -> Bool {
        guard upscaling == .lanczos, decoded.width > 0, decoded.height > 0 else { return false }
        return frame.width > decoded.width * 1.05 || frame.height > decoded.height * 1.05
    }

    /// The step nearest `value` in `steps`.
    public static func nearestIndex(_ value: Double, in steps: [Double]) -> Int {
        var best = 0
        for (i, s) in steps.enumerated() where abs(s - value) < abs(steps[best] - value) { best = i }
        return best
    }

    /// Moves `value` by `by` steps, clamped to the ends of `steps`.
    public static func stepped(_ value: Double, in steps: [Double], by: Int) -> Double {
        let i = min(steps.count - 1, max(0, nearestIndex(value, in: steps) + by))
        return steps[i]
    }

    public static func canStep(_ value: Double, in steps: [Double], by: Int) -> Bool {
        stepped(value, in: steps, by: by) != steps[nearestIndex(value, in: steps)]
    }

    /// "0", "+10%", "−20%".
    public static func brightnessLabel(_ value: Double) -> String {
        let percent = Int((brightnessSteps[nearestIndex(value, in: brightnessSteps)] * 100).rounded())
        if percent == 0 { return "0" }
        return percent > 0 ? "+\(percent)%" : "−\(-percent)%"
    }

    /// "100%", "120%".
    public static func contrastLabel(_ value: Double) -> String {
        "\(Int((contrastSteps[nearestIndex(value, in: contrastSteps)] * 100).rounded()))%"
    }
}
