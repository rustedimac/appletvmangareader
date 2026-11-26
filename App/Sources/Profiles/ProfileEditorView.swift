import SwiftUI
import MangaCore

/// Add or edit a profile: name, avatar symbol and color. Editing applies
/// each change right away (no Save button, docs/DESIGN_GUIDE.md); a new
/// profile is created with "Add Profile".
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let editing: Profile?
    @State private var name = ""
    @State private var symbol = ProfileAvatars.symbols[0]
    @State private var colorIndex = 0
    @State private var loaded = false
    @State private var confirmingDelete = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canDelete: Bool { editing != nil && model.state.profiles.count > 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profileEditor.name")
                    .font(SettingsFieldFont.text)

                VStack(alignment: .leading, spacing: Space.m) {
                header("Avatar")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.l), count: 6),
                          alignment: .leading, spacing: Space.l) {
                    ForEach(ProfileAvatars.symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            ProfileAvatarView(symbol: s, colorIndex: colorIndex, size: 88)
                                .opacity(s == symbol ? 1 : 0.5)
                        }
                        .buttonStyle(ProfileTileButtonStyle())
                        .accessibilityLabel(s)
                    }
                }
                }

                VStack(alignment: .leading, spacing: Space.m) {
                header("Color")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.l), count: ProfileAvatars.colorCount),
                          alignment: .leading, spacing: Space.l) {
                    ForEach(0..<ProfileAvatars.colorCount, id: \.self) { i in
                        Button { colorIndex = i } label: {
                            Circle()
                                .fill(ProfileColors.color(i))
                                .frame(width: 72, height: 72)
                                .overlay {
                                    if i == colorIndex {
                                        Image(systemName: "checkmark").font(.title3.bold()).foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(ProfileTileButtonStyle())
                        .accessibilityLabel("Color \(i + 1)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                }

                // ActionRow is a focus section, so focus moves down into the
                // buttons from anywhere in the rows above.
                if editing == nil || canDelete {
                    ActionRow {
                        if editing == nil {
                            Button { add() } label: {
                                Text("Add Profile").actionButtonSizing()
                            }
                            .disabled(trimmedName.isEmpty)
                            .accessibilityIdentifier("profileEditor.add")
                        }
                        if canDelete {
                            Button(role: .destructive) { confirmingDelete = true } label: {
                                Text("Delete Profile").actionButtonSizing()
                            }
                            .accessibilityIdentifier("profileEditor.delete")
                        }
                    }
                }
            }
            // Room for focused tiles to grow without clipping.
            .padding(.vertical, Space.l)
        }
        .settingsPage(editing == nil ? "New Profile" : "Edit Profile") {
            ProfileAvatarView(symbol: symbol, colorIndex: colorIndex, size: Size.heroSymbol)
        }
        .onAppear(perform: load)
        .onChange(of: name) { _, _ in applyEdit() }
        .onChange(of: symbol) { _, _ in applyEdit() }
        .onChange(of: colorIndex) { _, _ in applyEdit() }
        .confirmationDialog("Delete \(editing?.name ?? "")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let editing { model.removeProfile(editing.id) }
                dismiss()
            }
            .accessibilityIdentifier("profileEditor.confirmDelete")
        } message: {
            Text("Their favorites, local reading progress and server logins on this Apple TV are removed.")
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).sectionLabelStyle()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            name = editing.name
            symbol = editing.symbol
            colorIndex = editing.colorIndex
        } else {
            name = model.state.nextProfileName()
            colorIndex = model.state.profiles.count % ProfileAvatars.colorCount
            symbol = ProfileAvatars.symbols[model.state.profiles.count % ProfileAvatars.symbols.count]
        }
    }

    /// An existing profile takes each change as it's made. An empty name
    /// isn't stored; the last non-empty one stays.
    private func applyEdit() {
        guard loaded, let editing, !trimmedName.isEmpty,
              var profile = model.state.profiles.first(where: { $0.id == editing.id }) else { return }
        guard profile.name != trimmedName || profile.symbol != symbol || profile.colorIndex != colorIndex else { return }
        profile.name = trimmedName
        profile.symbol = symbol
        profile.colorIndex = colorIndex
        model.updateProfile(profile)
    }

    private func add() {
        guard editing == nil, !trimmedName.isEmpty else { return }
        model.addProfile(name: trimmedName, symbol: symbol, colorIndex: colorIndex)
        dismiss()
    }
}
