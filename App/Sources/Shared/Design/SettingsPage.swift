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
                .frame(maxWidth: Size.formColumn, maxHeight: .infinity)
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
