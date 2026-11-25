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
            VStack(alignment: .leading, spacing: 50) {
                HStack(spacing: 40) {
                    ProfileAvatarView(symbol: symbol, colorIndex: colorIndex, size: 160)
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 700)
                        .accessibilityIdentifier("profileEditor.name")
                }

                header("Avatar")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(110), spacing: 30), count: 9),
                          alignment: .leading, spacing: 30) {
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
                HStack(spacing: 30) {
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

                HStack(spacing: 40) {
                    Button(editing == nil ? "Add Profile" : "Save") { save() }
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("profileEditor.save")
                    if canDelete {
                        Button("Delete Profile", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("profileEditor.delete")
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 40)
        }
        .navigationTitle(editing == nil ? "New Profile" : "Edit Profile")
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
        Text(title).font(.headline).foregroundStyle(.secondary)
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
