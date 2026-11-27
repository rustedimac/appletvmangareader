import SwiftUI
import MangaCore

/// Settings section for starting a guest session.
struct GuestStartSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Button {
                model.startGuestSession()
            } label: {
                Label("Read as Guest", systemImage: GuestSession.profile.symbol)
            }
            .accessibilityIdentifier("settings.startGuest")
        } header: {
            SettingsHeader("Guest")
        } footer: {
            Text("A visitor can read from your servers without signing in. Nothing they read changes your progress, favorites or settings, and it's all cleared when the guest session ends.")
        }
    }
}

/// Settings section shown during a guest session, in place of the profile.
struct GuestSessionSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Button {
                model.endGuestSession()
            } label: {
                HStack(spacing: Space.m) {
                    ProfileAvatarView(profile: GuestSession.profile, size: Size.avatarRow)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(GuestSession.profile.name)
                        Text("End Guest Session").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("settings.endGuest")
        } header: {
            SettingsHeader("Profile")
        } footer: {
            Text("You're reading as a guest. Progress, favorites and bookmarks stay on this \(Platform.deviceName) until the session ends, and nothing is saved to the servers.")
        }
    }
}
