import SwiftUI

/// Tabs that switch between sections of one screen (the reader menu's
/// Settings / Chapters / Bookmarks), drawn like the app's top tab bar: a
/// rounded pill track holding text-only tabs, with the open tab shown as a
/// filled pill and the focused tab as the white pill tvOS uses for focus.
///
/// Use it for sections, never for a setting's value: a choice like On/Off or
/// Single/Double keeps its radio-style option chips (`OptionButton`) or a
/// picker, so tabs and choices never look alike. See docs/DESIGN_GUIDE.md,
/// "Section tabs".
///
/// Clicking a tab opens it; moving focus across the tabs doesn't, so focus
/// can pass over a tab on the way to another one without the pane below
/// rebuilding (and taking focus) under it.
///
/// Identifiers: each tab gets `identifier(tab)`, carries the `.isSelected`
/// trait when open; the track gets `trackIdentifier`.
struct SectionTabBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    let identifier: (Tab) -> String
    var focus: FocusState<String?>.Binding
    /// The focus key of a tab, matched against `focus`.
    let focusKey: (Tab) -> String
    let trackIdentifier: String

    var body: some View {
        HStack(spacing: SectionTabMetrics.tabSpacing) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: { Text(title(tab)) }
                    .buttonStyle(SectionTabStyle(isSelected: selection == tab))
                    .focused(focus, equals: focusKey(tab))
                    .accessibilityLabel(title(tab))
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityIdentifier(identifier(tab))
            }
        }
        .padding(SectionTabMetrics.trackInset)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .fixedSize()
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(trackIdentifier)
    }
}

enum SectionTabMetrics {
    /// Space between tabs inside the track.
    static let tabSpacing: CGFloat = Space.xs
    /// Track padding around the tabs.
    static let trackInset: CGFloat = Space.xs
    /// Tab label padding.
    static let labelHorizontal: CGFloat = Space.m + Space.xs
}

/// One tab: text only, one line, a capsule fill for the open and focused
/// states. No checkmarks or circles: those mean "a value you pick".
private struct SectionTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SectionTabLabel(configuration: configuration, isSelected: isSelected)
    }
}

private struct SectionTabLabel: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.callout.weight(isSelected || isFocused ? .semibold : .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(foreground)
            .padding(.horizontal, SectionTabMetrics.labelHorizontal)
            .frame(minHeight: Size.minTarget)
            .background(Capsule().fill(fill))
            .shadow(color: .black.opacity(isFocused ? 0.25 : 0), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.04 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private var fill: Color {
        if isFocused { return .white }
        if isSelected { return Color.primary.opacity(0.22) }
        return .clear
    }

    private var foreground: Color {
        if isFocused { return .black }
        return isSelected ? .primary : .secondary
    }
}
