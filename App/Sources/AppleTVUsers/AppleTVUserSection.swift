import SwiftUI
import MangaCore

/// Settings section shown when the app runs as the current Apple TV user:
/// the profile is that user, so it can be edited but not switched here.
struct AppleTVUserSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            NavigationLink {
                ProfileEditorView(editing: model.activeProfile)
            } label: {
                HStack(spacing: Space.m) {
                    ProfileAvatarView(profile: model.activeProfile, size: Size.avatarRow)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(model.activeProfile.name)
                        Text("Edit Name and Picture").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("settings.appleTVUser")
        } header: {
            SettingsHeader("Profile")
        } footer: {
            Text("Favorites, reading progress, reader settings and logins belong to whoever is signed in to this Apple TV. Switch users from Control Center. Servers are shared with every user, so they only need to be added once.")
        }
    }
}
