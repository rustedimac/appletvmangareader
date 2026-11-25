import SwiftUI
import MangaCore

/// "Who's reading?" Shown at launch when there's more than one profile, and
/// from Settings → Switch Profile.
struct ProfilePickerView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: UUID?
    @State private var showingManage = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 70) {
                Text("Who's reading?")
                    .font(.largeTitle.weight(.semibold))

                ScrollView(.horizontal) {
                    HStack(spacing: 60) {
                        ForEach(model.state.profiles) { profile in
                            Button {
                                model.pickProfile(profile.id)
                            } label: {
                                VStack(spacing: 24) {
                                    ProfileAvatarView(profile: profile, size: 220)
                                    Text(profile.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .frame(maxWidth: 260)
                                }
                            }
                            .buttonStyle(ProfileTileButtonStyle())
                            .focused($focused, equals: profile.id)
                            .accessibilityIdentifier("profilePicker.\(profile.name)")
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
                .scrollClipDisabled()
                .frame(maxWidth: .infinity)

                NavigationLink {
                    ProfilesListView()
                } label: {
                    Label("Manage Profiles", systemImage: "pencil")
                }
                .accessibilityIdentifier("profilePicker.manage")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { focused = model.activeProfile.id }
        }
    }
}
