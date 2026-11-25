import SwiftUI

/// The tvOS Settings layout: the page's symbol and title in a fixed column on
/// the leading side, and the form in a column of at most `Size.formColumn` on
/// the trailing side, so rows aren't stretched across the whole TV. See
/// docs/DESIGN_GUIDE.md §7.
///
/// The title lives in the hero column instead of `.navigationTitle`: a
/// navigation title above a scrolling form stays put on tvOS and ends up on
/// top of the rows, and it's centered on the screen rather than on the form.
///
/// ```swift
/// Form { … }
///     .settingsPage("Default Reader Settings", systemImage: "book")
/// ```
struct SettingsPage<Hero: View, Content: View>: View {
    private let title: String
    private let hero: Hero
    private let content: Content

    init(_ title: String, @ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hero = hero()
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.xxl) {
            VStack(spacing: Space.l) {
                hero
                    .frame(width: Size.heroSymbol, height: Size.heroSymbol)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settingsPage.title")
            }
            .frame(width: Size.heroColumn)
            .frame(maxHeight: .infinity)

            content
                // The form row is already the field's platter; the default
                // style would draw a second rounded box inside it.
                .textFieldStyle(.plain)
                .labelStyle(.settingsRow)
                // A focused row grows about 10 %; the list would clip it at
                // its own edges. The mask below does the clipping instead.
                .scrollClipDisabled()
                .frame(maxWidth: Size.formColumn, maxHeight: .infinity)
                // Rows scrolled up fade out at the top of the form instead
                // of sliding under the tab bar. The mask reaches past the
                // sides and bottom so focused rows are never cut off.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Space.l)
                        Rectangle()
                    }
                    .padding(.horizontal, -Space.xl)
                    .padding(.bottom, -Space.xxl)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settingsPage.form")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SettingsPage where Hero == SettingsHeroSymbol {
    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title, hero: { SettingsHeroSymbol(systemImage: systemImage) }, content: content)
    }
}

/// The default hero: a large secondary SF Symbol.
struct SettingsHeroSymbol: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .frame(width: Size.heroSymbol, height: Size.heroSymbol)
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Puts this form in a `SettingsPage` with a large symbol and the title
    /// beside it. A modifier rather than a wrapper so screens don't need
    /// re-indenting. Use it instead of `.navigationTitle`.
    func settingsPage(_ title: String, systemImage: String) -> some View {
        SettingsPage(title, systemImage: systemImage) { self }
    }

    /// Same, with a custom hero such as a profile avatar.
    func settingsPage<Hero: View>(_ title: String, @ViewBuilder hero: () -> Hero) -> some View {
        SettingsPage(title, hero: hero) { self }
    }
}

/// Settings rows: the icon in a fixed `Size.avatarRow` column with `Space.m`
/// before the title, so icons never touch their labels and every row's text
/// starts at the same x as rows that show an avatar.
struct SettingsRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.m) {
            configuration.icon
                .frame(width: Size.avatarRow)
            configuration.title
        }
    }
}

extension LabelStyle where Self == SettingsRowLabelStyle {
    static var settingsRow: SettingsRowLabelStyle { SettingsRowLabelStyle() }
}

/// A section header in a settings form. The same size, case and spacing on
/// every page, whether the screen is a `Form` or a `List`: `Space.m` above
/// it, so sections are clearly apart, and `Space.s` below, so the header
/// sits with its own rows.
struct SettingsHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .lineLimit(1)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .accessibilityAddTraits(.isHeader)
    }
}

extension Section where Parent == SettingsHeader, Footer == EmptyView, Content: View {
    /// `Section(settingsHeader: "Reading") { … }`
    init(settingsHeader title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SettingsHeader(title) })
    }
}
