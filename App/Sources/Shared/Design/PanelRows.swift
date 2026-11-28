import SwiftUI

/// Rows for settings that live outside a `Form`: the reader menu drawers
/// and custom settings pages such as Customize Home. They look and behave
/// like the rows of a settings form (and like Apple's own tvOS Settings):
/// one full-width platter per setting, the setting's name on the leading
/// side and its current value on the trailing side. See
/// docs/DESIGN_GUIDE.md, "Value rows outside a form".
///
/// - `PanelValueRow(…, kind: .opensChoices)`: value and chevron; a click
///   opens the choices (`PanelChoiceList` in a drawer, or a pushed page
///   through `SettingsPicker` on a settings page).
/// - `PanelValueRow(…, kind: .toggle)`: "On"/"Off" and no chevron; a click
///   flips it, like a `Toggle` in a form.
///
/// Never lay a setting's values out as side-by-side chips: labels of
/// different lengths wrap to different heights, and a row of chips reads
/// as a row of separate actions.
enum RowMetrics {
    /// Breathing room between a row's text and the top and bottom of its
    /// platter, on top of the system button padding. Text never touches the
    /// platter edge, and every row keeps the same height because labels are
    /// one line (`lineLimit(1)`).
    static let textInset: CGFloat = Space.xs
    /// Touch screens: every row is at least a 44 pt target. tvOS rows are
    /// sized by the system button.
    static let minHeight: CGFloat? = Platform.isTV ? nil : Size.minTarget
}

struct PanelValueRow: View {
    enum Kind {
        case opensChoices
        case toggle
    }

    let title: String
    let value: String
    var kind: Kind = .opensChoices
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsValueRow(title: title, value: value, showsChevron: kind == .opensChoices)
                .padding(.vertical, RowMetrics.textInset)
                .frame(maxWidth: .infinity, minHeight: RowMetrics.minHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

extension PanelValueRow {
    /// A toggle row: "On" or "Off", flipped by a click.
    init(title: String, isOn: Bool, toggle: @escaping () -> Void) {
        self.init(title: title, value: isOn ? "On" : "Off", kind: .toggle, action: toggle)
    }
}

/// One choice in a `PanelChoiceList`.
struct PanelChoice: Identifiable, Hashable {
    /// Stable key, used in the accessibility identifier and the focus key.
    let id: String
    let title: String
}

/// The choices of one `PanelValueRow`, shown in place of the rows inside a
/// drawer (which has no navigation stack to push a page onto): the
/// setting's name, then one full-width row per choice with a checkmark on
/// the current one. Picking a row applies it and goes back to the rows;
/// Menu goes back without changing anything (the drawer handles that).
///
/// Each choice gets the identifier `"\(identifierPrefix).\(choice.id)"`
/// and the focus key `"\(focusPrefix).\(choice.id)"`.
struct PanelChoiceList: View {
    let title: String
    let choices: [PanelChoice]
    let selected: String
    let identifierPrefix: String
    let focusPrefix: String
    var focus: FocusState<String?>.Binding
    var footnote: String? = nil
    let pick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("\(identifierPrefix).title")
            ForEach(choices) { choice in
                let isSelected = choice.id == selected
                Button {
                    pick(choice.id)
                } label: {
                    HStack(spacing: Space.m) {
                        Text(choice.title)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, RowMetrics.textInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focused(focus, equals: "\(focusPrefix).\(choice.id)")
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("\(identifierPrefix).\(choice.id)")
            }
            Text(footnote ?? "Press Menu to go back without changing it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
        .tvFocusSection()
    }
}

/// A help line under a row in a drawer or custom settings page: the same
/// style as a form footer.
struct PanelFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.m)
    }
}

extension View {
    /// Gives an icon-only button label the height of one line of text in
    /// the current font, plus `RowMetrics.textInset` above and below, so an
    /// icon button beside a text button (stepper − and +, Home row arrows)
    /// has exactly the same height.
    func lineHeightLabel() -> some View {
        ZStack {
            Text("Ag").hidden().accessibilityHidden(true)
            self
        }
        .padding(.vertical, RowMetrics.textInset)
    }
}
