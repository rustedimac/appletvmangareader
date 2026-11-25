import SwiftUI
import MangaCore

/// "Who's reading?" Shown at launch when there's more than one profile, and
/// from Settings → Switch Profile.
struct ProfilePickerView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: UUID?
    @State private var showingManage = false
    /// The profile waiting for its PIN before it opens.
    @State private var unlocking: Profile?

    var body: some View {
        NavigationStack {
            VStack(spacing: 70) {
                Text("Who's reading?")
                    .font(.largeTitle.weight(.semibold))

                // Centered when the profiles fit on screen; scrolls when they don't.
                ViewThatFits(in: .horizontal) {
                    profileRow
                    ScrollView(.horizontal) { profileRow }
                        .scrollClipDisabled()
                }
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
            .navigationDestination(item: $unlocking) { profile in
                PINPadView(title: "Enter \(profile.name)'s PIN") { pin in
                    let result = model.attemptPIN(pin, candidates: [profile.id])
                    if case .unlocked = result {
                        unlocking = nil
                        open(profile)
                    }
                    return PINGate<EmptyView>.feedback(result)
                }
            }
        }
    }

    private var profileRow: some View {
        HStack(spacing: 60) {
            ForEach(model.state.profiles) { profile in
                Button {
                    if model.needsPINToOpen(profile.id) {
                        unlocking = profile
                    } else {
                        open(profile)
                    }
                } label: {
                    VStack(spacing: 24) {
                        ProfileAvatarView(profile: profile, size: 220)
                            .overlay(alignment: .bottomTrailing) {
                                if model.requiresPINToOpen(profile.id) && model.hasPIN(profile.id) {
                                    Image(systemName: "lock.fill")
                                        .font(.title3)
                                        .padding(12)
                                        .background(.thinMaterial, in: Circle())
                                        .padding(10)
                                }
                            }
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

    private func open(_ profile: Profile) {
        model.switchProfile(profile.id)
        model.isPickingProfile = false
    }
}
