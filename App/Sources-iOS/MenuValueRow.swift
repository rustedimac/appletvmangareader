import SwiftUI

/// Sets an accessibility identifier only when there is one, so a caller's
/// own identifier on the row isn't replaced by an empty one.
private struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// One choice in a `MenuValueRow`.
struct MenuChoice<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
}

/// The iOS Settings row for picking one of a few values: the name on the
/// leading side, the current value and an up/down chevron on the trailing
/// side; tapping opens the system pop-up menu with a checkmark on the current
/// choice. Used for every choice on iPhone and iPad (reader options and
/// settings pages), in place of the TV's in-place choice list.
///
/// The row's accessibility identifier goes on the menu button; the menu's
/// items are buttons named by their titles.
struct MenuValueRow<ID: Hashable>: View {
    let title: String
    let choices: [MenuChoice<ID>]
    let selected: ID
    let pick: (ID) -> Void
    var identifier: String? = nil

    private var value: String {
        let match: MenuChoice<ID>? = choices.first { $0.id == selected }
        return match?.title ?? ""
    }

    var body: some View {
        HStack(spacing: Space.m) {
            // The name gives way first when space is short.
            Text(title)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer(minLength: Space.s)
            Menu {
                Picker(title, selection: Binding<ID>(get: { selected }, set: { pick($0) })) {
                    ForEach(choices) { choice in
                        Text(choice.title).tag(choice.id)
                    }
                }
            } label: {
                HStack(spacing: Space.xs) {
                    // Full width at once: a new, longer value used to show
                    // cut off while the label animated its width.
                    Text(value)
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.identity)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: Size.minTarget)
                .contentShape(Rectangle())
                .transaction { $0.animation = nil }
            }
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .modifier(OptionalIdentifier(identifier: identifier))
        }
        .frame(minHeight: Size.minTarget)
    }
}
