import SwiftUI
import MangaCore

/// Add or edit a profile: name, avatar symbol and color.
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
            VStack(alignment: .leading, spacing: Space.xl) {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profileEditor.name")

                header("Avatar")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(110), spacing: Space.l), count: 6),
                          alignment: .leading, spacing: Space.l) {
                    ForEach(ProfileAvatars.symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            ProfileAvatarView(symbol: s, colorIndex: colorIndex, size: 96)
                                .opacity(s == symbol ? 1 : 0.5)
                        }
                        .buttonStyle(ProfileTileButtonStyle())
                        .accessibilityLabel(s)
                    }
                }

                header("Color")
                HStack(spacing: Space.l) {
                    ForEach(0..<ProfileAvatars.colorCount, id: \.self) { i in
                        Button { colorIndex = i } label: {
                            Circle()
                                .fill(ProfileColors.color(i))
                                .frame(width: 80, height: 80)
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

                // ActionRow is a focus section, so focus moves down into the
                // buttons from anywhere in the rows above.
                ActionRow {
                    Button { save() } label: {
                        Text(editing == nil ? "Add Profile" : "Save").actionButtonSizing()
                    }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier("profileEditor.save")
                    if canDelete {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Text("Delete Profile").actionButtonSizing()
                        }
                        .accessibilityIdentifier("profileEditor.delete")
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

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if var profile = editing {
            profile.name = trimmedName
            profile.symbol = symbol
            profile.colorIndex = colorIndex
            model.updateProfile(profile)
        } else {
            model.addProfile(name: trimmedName, symbol: symbol, colorIndex: colorIndex)
        }
        dismiss()
    }
}
