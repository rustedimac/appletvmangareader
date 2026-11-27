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
    /// The theme's own buttons and rows (see `ThemeControls`); nil keeps the
    /// system's platters and white focus.
    let controls: ThemeControls?

    static let standard = ThemeStyle(colorScheme: .dark, background: nil, tint: nil, text: nil, heading: nil,
                                     sectionLabel: nil, headingEcho: nil, brushStroke: nil, headingFace: nil,
                                     controls: nil)

    static func of(_ theme: AppTheme) -> ThemeStyle {
        switch theme {
        case .standard:
            return .standard
        case .celadon, .tenmoku:
            let p = CeladonTheme.palette()
            // Theme Lab tvOS: glazed plates on the clay body; the focused
            // tile pools into focus-surface with a wet glaze-rim and lifts;
            // the open item is the cobalt-tinged selection glaze, so it never
            // looks like the focused one.
            return ThemeStyle(colorScheme: theme.isLight ? .light : .dark, background: p.bg, tint: p.tint,
                              text: (p.ink, p.inkMuted),
                              heading: p.ink, sectionLabel: p.inkMuted, headingEcho: nil,
                              brushStroke: p.brush, headingFace: "AlegreyaRoman-Bold",
                              controls: ThemeControls(plate: p.glaze, plateText: p.ink, plateSecondary: p.inkMuted,
                                                      focus: p.focusSurface, focusText: p.onFocusSurface,
                                                      selected: p.selection, selectedText: p.selectionInk,
                                                      rim: p.glazeRim, foot: p.ironFoot, echo: nil,
                                                      shape: .glazed))
        case .newsprint, .blackStock:
            let p = RisographTheme.palette()
            // Theme Lab tvOS: square plates in a key-ink wash; the focused
            // tile prints as a solid key plate with the flare drum's second
            // pass misregistered behind it; the open item is a highlighter
            // plate (yellow sun on newsprint, gold flare on black stock, where
            // the white sun plate would look like the system focus).
            return ThemeStyle(colorScheme: theme.isLight ? .light : .dark, background: p.paper, tint: p.tint,
                              text: (p.ink, p.inkSoft),
                              heading: p.key, sectionLabel: p.inkSoft, headingEcho: p.flare,
                              brushStroke: nil, headingFace: "LondrinaSolid-Black",
                              controls: ThemeControls(plate: p.washKey, plateText: p.ink, plateSecondary: p.inkSoft,
                                                      focus: p.focusSurface, focusText: p.onFocusSurface,
                                                      selected: theme == .blackStock ? p.flare : p.sun,
                                                      selectedText: theme == .blackStock ? p.onFlare : p.onSun,
                                                      rim: nil, foot: nil, echo: p.flare,
                                                      shape: .square))
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
            .modifier(ThemedButtons(themed: style.controls != nil))
            .modifier(TextColors(colors: style.text))
            .background {
                if let ground = style.background {
                    ground.ignoresSafeArea()
                }
            }
    }
}

/// The theme's button style, or no style at all without a theme: even a
/// pass-through style changes how system controls built on buttons (form
/// Pickers) are put together, so the default theme sets none. Switching
/// between a theme and the default rebuilds the screens below.
private struct ThemedButtons: ViewModifier {
    let themed: Bool

    func body(content: Content) -> some View {
        if themed {
            content.buttonStyle(ThemedButtonStyle())
        } else {
            content
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

// MARK: Themed controls

/// How a theme draws buttons and rows, after its Theme Lab tvOS sample
/// (`themes/<slug>/components/ApplePlatforms`): every button is a plate in
/// the theme's surface color; the focused one fills with the theme's focus
/// surface, lifts and grows; an open item (the current library, the picked
/// category) shows in the selected color.
///
/// Every text color is one of the theme's checked pairs on the fill it sits
/// on: `plateText`/`plateSecondary` on `plate`, `focusText` on `focus`,
/// `selectedText` on `selected`. tools/check_theme_contrast.py checks them
/// in CI against the generated palettes.
struct ThemeControls {
    enum Shape {
        /// Celadon: soft continuous corners (glaze rounds every edge), a wet
        /// rim line along the top and an iron foot line under the plate.
        case glazed
        /// Risograph: square plates; the focused one gets the flare drum's
        /// second pass printed a few points down-right behind it.
        case square
    }

    let plate: Color
    let plateText: Color
    let plateSecondary: Color
    let focus: Color
    let focusText: Color
    let selected: Color
    let selectedText: Color
    /// Celadon's glaze rim on the focused plate.
    let rim: Color?
    /// Celadon's iron foot under every plate.
    let foot: Color?
    /// Risograph's misregistered second pass behind the focused plate.
    let echo: Color?
    let shape: Shape

    /// Theme Lab `tvos-focus-scale`.
    static let focusScale: CGFloat = 1.06
    /// Theme Lab `tvos-focus-lift`, the lift of the focused plate.
    static let focusLift: CGFloat = 10
    /// Risograph's second-pass offset.
    static let echoOffset = CGSize(width: 7, height: 6)
}

private struct ControlSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ControlFillsRowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The button stands for the open item of a group (the category on
    /// screen, the current choice). Themes draw it in their selected color.
    var controlIsSelected: Bool {
        get { self[ControlSelectedKey.self] }
        set { self[ControlSelectedKey.self] = newValue }
    }

    /// Buttons are rows of a settings form (`SettingsPage`): a theme's plate
    /// spans the row and replaces the row's own platter, so there is one
    /// plate per row, not a small one inside a big one.
    var controlFillsRow: Bool {
        get { self[ControlFillsRowKey.self] }
        set { self[ControlFillsRowKey.self] = newValue }
    }
}

extension View {
    /// Marks a button as the open item of its group (see `controlIsSelected`).
    /// Without a theme the system button tints it with the accent color.
    func controlSelected(_ isSelected: Bool) -> some View {
        environment(\.controlIsSelected, isSelected)
            .tint(isSelected ? Color.accentColor : nil)
    }

    /// A check mark or similar "this one is on" glyph: the accent color
    /// without a theme; with one, the label's own color, because a theme's
    /// focused plate is often the accent color itself.
    func themedMark(_ isOn: Bool) -> some View {
        modifier(ThemedMark(isOn: isOn))
    }

    /// Screens that keep the system look whatever the theme (the reader).
    func unthemed() -> some View {
        environment(\.themeStyle, .standard)
    }
}

/// The app-wide button style: the system's own buttons without a theme, the
/// theme's plates with one. Buttons that pick a style themselves (posters'
/// `.card`, profile tiles, section tabs) keep theirs.
struct ThemedButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ThemedButton(configuration: configuration)
    }
}

private struct ThemedMark: ViewModifier {
    let isOn: Bool
    @Environment(\.themeStyle) private var theme

    func body(content: Content) -> some View {
        if theme.controls != nil {
            // Monochrome: a plate's two text styles would otherwise paint a
            // filled symbol's cut-out (the tick in checkmark.circle.fill) too.
            content.symbolRenderingMode(.monochrome)
                .foregroundStyle(isOn ? .primary : .secondary)
        } else {
            content.foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
    }
}

private struct ThemedButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.themeStyle) private var theme
    @Environment(\.controlFillsRow) private var fillsRow

    var body: some View {
        if let controls = theme.controls {
            Button(configuration)
                .buttonStyle(ThemePlateStyle(controls: controls, fillsRow: fillsRow))
                // One plate per row: the theme's, not the form's as well.
                .listRowBackground(fillsRow ? Color.clear : nil)
        } else {
            Button(configuration)
                .buttonStyle(.automatic)
        }
    }
}

/// One plate: fill, text colors, focus lift and the theme's marks.
private struct ThemePlateStyle: ButtonStyle {
    let controls: ThemeControls
    let fillsRow: Bool

    func makeBody(configuration: Configuration) -> some View {
        ThemePlate(configuration: configuration, controls: controls, fillsRow: fillsRow)
    }
}

private struct ThemePlate: View {
    let configuration: ButtonStyleConfiguration
    let controls: ThemeControls
    let fillsRow: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.controlIsSelected) private var isSelected
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fill: Color {
        if isFocused { return controls.focus }
        return isSelected ? controls.selected : controls.plate
    }

    private var text: (Color, Color) {
        if isFocused { return (controls.focusText, controls.focusText) }
        if isSelected { return (controls.selectedText, controls.selectedText) }
        return (controls.plateText, controls.plateSecondary)
    }

    private var radius: CGFloat {
        controls.shape == .glazed ? Radius.card : 0
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .foregroundStyle(text.0, text.1)
            .frame(maxWidth: fillsRow ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, Space.m + Space.xs)
            .padding(.vertical, fillsRow ? Space.xs : Space.s)
            .frame(minHeight: Size.minTarget)
            .background {
                ZStack {
                    if isFocused, let echo = controls.echo {
                        shape.fill(echo)
                            .offset(ThemeControls.echoOffset)
                    }
                    shape.fill(fill)
                    if let rim = controls.rim, isFocused {
                        // The wet rim: a bright inset line along the top edge.
                        shape.strokeBorder(rim.opacity(0.7), lineWidth: 2)
                            .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                    }
                    if let foot = controls.foot {
                        // The unglazed foot: a thin iron line under the plate.
                        shape.strokeBorder(foot, lineWidth: 2)
                            .mask(LinearGradient(colors: [.clear, .clear, .white], startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(shape)
            .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: isFocused ? 18 : 0, y: isFocused ? 12 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? ThemeControls.focusScale : 1))
            .offset(y: isFocused ? -ThemeControls.focusLift / 2 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.36), value: isFocused)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
