import SwiftUI
import MangaCore

/// Settings → Manage Profiles.
struct ProfilesListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(model.state.profiles) { profile in
                    NavigationLink {
                        PINGate(kind: .profile(profile.id), reason: "Enter the PIN to edit this profile.") {
                            ProfileEditorView(editing: profile)
                        }
                    } label: {
                        HStack(spacing: Space.m) {
                            ProfileAvatarView(profile: profile, size: Size.avatarRow)
                            Text(profile.name)
                            if model.hasPIN(profile.id) {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            }
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
                    PINGate(kind: .anyProtected, reason: "A profile on this \(Platform.deviceName) has a PIN. Enter one to add a profile.") {
                        ProfileEditorView(editing: nil)
                    }
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .accessibilityIdentifier("profiles.add")
            }
        }
        .settingsPage("Profiles", systemImage: "person.2")
    }
}
