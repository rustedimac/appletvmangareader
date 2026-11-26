import Foundation

/// The app's look outside the reader (Settings > Theme). A profile setting,
/// synced with the rest of `BrowsePreferences`. The reader keeps its own
/// page background and colors whatever the theme.
///
/// The Celadon and Risograph themes come from Theme Lab
/// (github.com/rustedimac/theme-lab); each has a light and a dark side, which
/// are separate choices here because the app doesn't follow the system
/// appearance (see `UIUserInterfaceStyle` in project.yml).
public enum AppTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The system's dark look the app has always had.
    case standard
    /// Celadon: jade-grey glaze over porcelain (light).
    case celadon
    /// Celadon's dark side: iron-black tenmoku glaze with amber streaks.
    case tenmoku
    /// Risograph on natural newsprint (light): blue and pink spot inks.
    case newsprint
    /// Risograph on black card stock (dark): pink, gold and white inks.
    case blackStock

    public static let `default` = AppTheme.standard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Default"
        case .celadon: return "Celadon"
        case .tenmoku: return "Celadon Tenmoku"
        case .newsprint: return "Risograph Newsprint"
        case .blackStock: return "Risograph Black Stock"
        }
    }

    /// Light themes switch the whole app to the light appearance.
    public var isLight: Bool {
        switch self {
        case .celadon, .newsprint: return true
        case .standard, .tenmoku, .blackStock: return false
        }
    }
}
