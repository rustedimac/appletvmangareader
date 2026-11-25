import SwiftUI
import MangaCore

/// Settings for the built-in Free Library: what it is, the credits its
/// licenses ask for, which collections to show, and removing it.
struct FreeLibrarySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig

    @State private var confirmingRemove = false
    @State private var summary: String?

    var body: some View {
        Form {
            ScreenTitle(FreeLibrary.name)
            Section {
                Text(FreeLibrary.about)
                    .accessibilityIdentifier("freeLibrary.about")
                if let summary {
                    Text(summary).foregroundStyle(.secondary)
                }
            }

            Section("Credits") {
                ForEach(Array(FreeLibrary.credits.enumerated()), id: \.offset) { i, credit in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(credit.title).font(.headline)
                        Text(credit.detail).font(.callout).foregroundStyle(.secondary)
                    }
                    .focusable()
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("freeLibrary.credit.\(i)")
                }
            }

            Section {
                NavigationLink {
                    CategorySelectionView(server: server)
                } label: {
                    Label("Choose Collections", systemImage: "checklist")
                }
                .accessibilityIdentifier("freeLibrary.collections")
            } footer: {
                Text("Progress in the Free Library is kept on this Apple TV, separately for each profile.")
            }

            Section {
                Button("Remove Free Library", role: .destructive) { confirmingRemove = true }
                    .accessibilityIdentifier("freeLibrary.remove")
            } footer: {
                Text("You can add it back from Settings at any time.")
            }
        }
        .task { summary = try? await model.client(for: server).validate() }
        .confirmationDialog("Remove the Free Library?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.removeServer(server)
                dismiss()
            }
            .accessibilityIdentifier("freeLibrary.confirmRemove")
        } message: {
            Text("Favorites and progress for Free Library titles are removed from every profile.")
        }
    }
}
