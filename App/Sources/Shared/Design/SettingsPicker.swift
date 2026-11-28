import SwiftUI

/// A settings row that picks one value from a list, laid out like the rows
/// in Apple's own tvOS Settings: title on the leading side, the current
/// value in `.secondary` with the chevron `Space.s` after it, both on the
/// trailing side. Selecting the row opens the choices on their own page.
///
/// Use it instead of `Picker` in a settings `Form`. The system picker leaves
/// a gap of about 60 pt between the value and its chevron, about twice what
/// Apple's Settings app uses, and SwiftUI offers no way to change it. See
/// docs/DESIGN_GUIDE.md §7 "Pickers".
///
/// ```swift
/// SettingsPicker("Mode", selection: $settings.mode, options: ReadingMode.allCases) { $0.title }
/// ```
///
/// It must sit inside a `SettingsPage` (which every settings form uses) in a
/// `NavigationStack`; the page owns the navigation to the choices.
struct SettingsPicker<Value: Hashable>: View {
    private let title: String
    @Binding private var selection: Value
    private let options: [Value]
    private let systemImage: String
    private let label: (Value) -> String
    private let footnote: String?

    @Environment(\.settingsNavigator) private var navigator
    @Environment(\.settingsRowsOutsideForm) private var outsideForm

    /// - Parameters:
    ///   - systemImage: the symbol in the hero column of the page that
    ///     lists the choices.
    ///   - footnote: shown under the choices.
    init(_ title: String, selection: Binding<Value>, options: [Value], systemImage: String = "list.bullet",
         footnote: String? = nil, label: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.options = options
        self.systemImage = systemImage
        self.footnote = footnote
        self.label = label
    }

    var body: some View {
        #if os(iOS)
        // iPhone/iPad: the system pop-up menu in the row, like iOS Settings.
        let choices: [MenuChoice<Int>] = options.indices.map { MenuChoice(id: $0, title: label(options[$0])) }
        let current: Int = options.firstIndex(of: selection) ?? 0
        MenuValueRow(title: title, choices: choices, selected: current,
                     pick: { selection = options[$0] })
        #else
        tvBody
        #endif
    }

    private var tvBody: some View {
        Button {
            guard let navigator else {
                assertionFailure("SettingsPicker needs to be inside a SettingsPage")
                return
            }
            navigator.show(SettingsPickerChoices(title: title, selection: $selection, options: options,
                                                 systemImage: systemImage, footnote: footnote, label: label))
        } label: {
            if outsideForm {
                // A plain button has no row padding of its own.
                SettingsValueRow(title: title, value: label(selection))
                    .padding(.vertical, RowMetrics.textInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SettingsValueRow(title: title, value: label(selection))
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

/// The inside of a row that shows a value and opens another page: title,
/// then value and chevron pinned to the trailing edge, `Space.s` apart, the
/// same whether or not the row has focus. The value never truncates before
/// the title does. Without the chevron (`showsChevron: false`) it's the
/// inside of a toggle row: the value ("On"/"Off") ends where a chevron
/// would, like a form `Toggle`.
struct SettingsValueRow: View {
    let title: String
    let value: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: Space.m) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: Space.s) {
                Text(value)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                if showsChevron {
                    SettingsChevron()
                }
            }
            .layoutPriority(1)
        }
    }
}

/// The trailing chevron of a row that opens another page.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .imageScale(.small)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// The page a `SettingsPicker` opens: one row per choice, a checkmark on
/// the current one, focus starting on it. Choosing a row goes back.
struct SettingsPickerChoices<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let systemImage: String
    var footnote: String? = nil
    let label: (Value) -> String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Value?

    var body: some View {
        Form {
            Section {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        dismiss()
                    } label: {
                        HStack(spacing: Space.m) {
                            Text(label(option))
                            Spacer(minLength: 0)
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .focused($focused, equals: option)
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
                    .accessibilityIdentifier("settingsPicker.option.\(label(option))")
                }
            } footer: {
                if let footnote { Text(footnote) }
            }
        }
        .settingsPage(title, systemImage: systemImage)
        .defaultFocus($focused, selection)
    }
}

// MARK: - Navigation

/// Pushes pages for rows inside a `SettingsPage`. The page applies the
/// `navigationDestination` itself, outside the form, because SwiftUI
/// doesn't support navigation destinations inside lazy containers such as
/// a `Form`'s rows.
@Observable
@MainActor
final class SettingsNavigator {
    fileprivate(set) var destination: SettingsDestination?

    func show(_ view: some View) {
        destination = SettingsDestination(view: AnyView(view))
    }

    fileprivate var binding: Binding<SettingsDestination?> {
        Binding(get: { self.destination }, set: { self.destination = $0 })
    }
}

struct SettingsDestination: Identifiable, Hashable {
    let id = UUID()
    let view: AnyView

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct SettingsRowsOutsideFormKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SettingsNavigatorKey: EnvironmentKey {
    static let defaultValue: SettingsNavigator? = nil
}

extension EnvironmentValues {
    /// Set by `.settingsRowsOutsideForm()`: rows are plain buttons in a
    /// scroll view, so they add the row padding a form would give them.
    var settingsRowsOutsideForm: Bool {
        get { self[SettingsRowsOutsideFormKey.self] }
        set { self[SettingsRowsOutsideFormKey.self] = newValue }
    }

    var settingsNavigator: SettingsNavigator? {
        get { self[SettingsNavigatorKey.self] }
        set { self[SettingsNavigatorKey.self] = newValue }
    }
}

extension View {
    /// For a settings page built from a `ScrollView` instead of a `Form`
    /// (Customize Home): `SettingsPicker` rows fill the width and get the
    /// same text inset as `PanelValueRow`.
    func settingsRowsOutsideForm() -> some View {
        environment(\.settingsRowsOutsideForm, true)
    }

    /// Lets `SettingsPicker` rows in this view push their choices.
    func settingsNavigation(_ navigator: SettingsNavigator) -> some View {
        environment(\.settingsNavigator, navigator)
            .navigationDestination(item: navigator.binding) { $0.view }
    }
}
