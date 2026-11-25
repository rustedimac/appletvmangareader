import SwiftUI

/// The tvOS Settings layout: a large symbol on the leading side and the form
/// in a column of at most `Size.formColumn` on the trailing side, so rows
/// aren't stretched across the whole TV. See docs/DESIGN_GUIDE.md §7.
///
/// ```swift
/// SettingsPage(systemImage: "book") {
///     Form { … }
/// }
/// .navigationTitle("Default Reader Settings")
/// ```
struct SettingsPage<Hero: View, Content: View>: View {
    private let hero: Hero
    private let content: Content

    init(@ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content) {
        self.hero = hero()
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.xxl) {
            hero
                .frame(width: Size.heroColumn)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: Size.formColumn, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settingsPage.form")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SettingsPage where Hero == SettingsHeroSymbol {
    init(systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(hero: { SettingsHeroSymbol(systemImage: systemImage) }, content: content)
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
    /// Puts this form in a `SettingsPage` with a large symbol beside it.
    /// A modifier rather than a wrapper so screens don't need re-indenting.
    func settingsPage(systemImage: String) -> some View {
        SettingsPage(systemImage: systemImage) { self }
    }

    /// Puts this form in a `SettingsPage` with a custom hero, e.g. an avatar.
    func settingsPage<Hero: View>(@ViewBuilder hero: () -> Hero) -> some View {
        SettingsPage(hero: hero) { self }
    }
}
