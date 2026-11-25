import SwiftUI
import MangaCore

/// Settings → Manage Profiles.
struct ProfilesListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.state.profiles) { profile in
                    NavigationLink {
                        ProfileEditorView(editing: profile)
                    } label: {
                        HStack(spacing: 30) {
                            ProfileAvatarView(profile: profile, size: 64)
                            Text(profile.name)
                            Spacer()
                            if profile.id == model.activeProfile.id {
                                Text("Current").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("profiles.row.\(profile.name)")
                }
            } footer: {
                Text("Each profile has its own favorites, reading progress, reader settings and server logins.")
            }

            Section {
                NavigationLink {
                    ProfileEditorView(editing: nil)
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .accessibilityIdentifier("profiles.add")
            }
        }
        .settingsPage("Profiles", systemImage: "person.2")
    }
}
