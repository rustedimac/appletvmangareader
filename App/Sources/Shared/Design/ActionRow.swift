import SwiftUI

/// A row of action buttons outside a form: leading-aligned, `Space.l`
/// apart, primary first and destructive last. Wrap each button label in
/// `.actionButtonSizing()` so short labels aren't stubby and long ones
/// don't become bars.
struct ActionRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: Space.l) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

extension View {
    /// Keeps a text button's label between `Size.buttonMinWidth` and
    /// `Size.buttonMaxWidth`, on one line. Apply to the label, not the
    /// button, so the system platter grows with it.
    func actionButtonSizing() -> some View {
        lineLimit(1)
            .frame(minWidth: Size.buttonMinWidth - 2 * Space.l, maxWidth: Size.buttonMaxWidth - 2 * Space.l)
    }

    /// A section label on a custom (non-Form) page.
    func sectionLabelStyle() -> some View {
        font(.headline).foregroundStyle(.secondary)
    }
}
