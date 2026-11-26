import SwiftUI
import MangaCore
import CeladonTheme
import RisographTheme

/// What an `AppTheme` changes on screen. The themes come from Theme Lab
/// (Packages/Themes); this picks the few roles tvOS screens need. Everything
/// focusable keeps the system focus effects (white platter, lift), so only
/// grounds, headings, section labels, secondary text and the tint change.
///
/// Every text color here is one of the theme's own checked pairs on its
/// ground (Theme Lab `contrast.json`): Celadon `ink` and `ink-muted` on `bg`,
/// Risograph `key`, `ink` and `ink-soft` on `paper`.
struct ThemeStyle {
    /// The appearance the whole app uses with this theme.
    let colorScheme: ColorScheme
    /// The screen ground behind everything; nil keeps the system's.
    let background: Color?
    /// `.tint` for toggles, progress and `Color.accentColor`.
    let tint: Color?
    /// Body and secondary text on light themes. Dark themes keep the
    /// system's, because tvOS draws focused rows on a white platter and a
    /// light theme ink would vanish on it.
    let text: (primary: Color, secondary: Color)?
    /// Screen titles.
    let heading: Color?
    /// Section labels and shelf titles.
    let sectionLabel: Color?
    /// Risograph's misregistered second pass behind headings.
    let headingEcho: Color?
    /// Celadon's brush stroke under page titles.
    let brushStroke: Color?
    /// PostScript name of the heading face (bundled in App/Resources/Fonts).
    let headingFace: String?

    static let standard = ThemeStyle(colorScheme: .dark, background: nil, tint: nil, text: nil, heading: nil,
                                     sectionLabel: nil, headingEcho: nil, brushStroke: nil, headingFace: nil)

    static func of(_ theme: AppTheme) -> ThemeStyle {
        switch theme {
        case .standard:
            return .standard
        case .celadon, .tenmoku:
            let p = CeladonTheme.palette()
            return ThemeStyle(colorScheme: theme.isLight ? .light : .dark, background: p.bg, tint: p.tint,
                              text: theme.isLight ? (p.ink, p.inkMuted) : nil,
                              heading: p.ink, sectionLabel: p.inkMuted, headingEcho: nil,
                              brushStroke: p.brush, headingFace: "AlegreyaRoman-Bold")
        case .newsprint, .blackStock:
            let p = RisographTheme.palette()
            return ThemeStyle(colorScheme: theme.isLight ? .light : .dark, background: p.paper, tint: p.tint,
                              text: theme.isLight ? (p.ink, p.inkSoft) : nil,
                              heading: p.key, sectionLabel: p.inkSoft, headingEcho: p.flare,
                              brushStroke: nil, headingFace: "LondrinaSolid-Black")
        }
    }

    /// A heading font: the theme's face at the size of `style`, else `fallback`.
    func headingFont(_ style: Font.TextStyle, fallback: Font) -> Font {
        guard let headingFace else { return fallback }
        return Font.custom(headingFace, size: Self.tvSize(style), relativeTo: style)
    }

    /// tvOS sizes of the system text styles at the default Dynamic Type size.
    private static func tvSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle, .title: return 76
        case .title2: return 57
        case .title3: return 48
        case .headline: return 38
        case .callout: return 31
        case .body, .subheadline: return 29
        case .caption: return 25
        default: return 23
        }
    }
}

private struct ThemeStyleKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.standard
}

extension EnvironmentValues {
    var themeStyle: ThemeStyle {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }
}

extension View {
    /// Applies a theme to everything below: appearance, tint, text colors
    /// and the ground. Set once at the root; full-screen covers get it again
    /// with `themedScreen()`.
    func appTheme(_ theme: AppTheme) -> some View {
        let style = ThemeStyle.of(theme)
        return environment(\.themeStyle, style)
            .modifier(ThemedScreen(style: style))
            .preferredColorScheme(style.colorScheme)
    }

    /// The theme's ground and text colors behind a screen. Pushed and
    /// presented screens get an opaque system background of their own on
    /// tvOS, so each one paints the ground again.
    func themedScreen() -> some View {
        modifier(ThemedScreenFromEnvironment())
    }

    /// A screen or page title in the theme's heading face and color.
    func themedHeading(_ style: Font.TextStyle, fallback: Font) -> some View {
        modifier(ThemedHeading(textStyle: style, fallback: fallback, role: .title))
    }

    /// A section label or shelf title in the theme's heading face and label color.
    func themedSectionLabel(_ style: Font.TextStyle, fallback: Font) -> some View {
        modifier(ThemedHeading(textStyle: style, fallback: fallback, role: .section))
    }
}

private struct ThemedScreenFromEnvironment: ViewModifier {
    @Environment(\.themeStyle) private var style
    func body(content: Content) -> some View {
        content.modifier(ThemedScreen(style: style))
    }
}

private struct ThemedScreen: ViewModifier {
    let style: ThemeStyle

    func body(content: Content) -> some View {
        content
            .tint(style.tint)
            .modifier(TextColors(colors: style.text))
            .background {
                if let ground = style.background {
                    ground.ignoresSafeArea()
                }
            }
    }
}

private struct TextColors: ViewModifier {
    let colors: (primary: Color, secondary: Color)?

    func body(content: Content) -> some View {
        if let colors {
            content.foregroundStyle(colors.primary, colors.secondary)
        } else {
            content
        }
    }
}

private struct ThemedHeading: ViewModifier {
    enum Role { case title, section }
    let textStyle: Font.TextStyle
    let fallback: Font
    let role: Role
    @Environment(\.themeStyle) private var style

    func body(content: Content) -> some View {
        let color = role == .title ? style.heading : style.sectionLabel
        content
            .font(style.headingFont(textStyle, fallback: fallback))
            .modifier(OptionalForeground(color: color, fallback: role == .section))
            // Risograph: the flare drum lands a few points off the key drum.
            // Titles only; labels are too small for a second pass to read.
            .shadow(color: role == .title ? (style.headingEcho ?? .clear) : .clear, radius: 0, x: 4, y: 4)
    }
}

/// `color` when the theme sets one; otherwise `.secondary` for section
/// labels (their look before themes) and the inherited style for titles.
private struct OptionalForeground: ViewModifier {
    let color: Color?
    let fallback: Bool

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else if fallback {
            content.foregroundStyle(.secondary)
        } else {
            content
        }
    }
}

/// Celadon's brush stroke: a short tapered cobalt (or oil-spot silver) mark
/// under a page title. Nothing in other themes.
struct ThemeBrushStroke: View {
    @Environment(\.themeStyle) private var style

    var body: some View {
        if let color = style.brushStroke {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 120, height: 6)
                .accessibilityHidden(true)
        }
    }
}
