import Foundation
import TVServices
import MangaCore

/// tvOS user management. With the `com.apple.developer.user-management`
/// entitlement set to `runs-as-current-user-with-user-independent-keychain`
/// the system gives every Apple TV user their own copy of the app's data,
/// and `shouldStorePreferencesForCurrentUser` is true while more than one
/// person uses the Apple TV. Then:
///
/// - the Apple TV user is the profile: each user's copy of the state starts
///   with one profile of their own (favorites, progress, reader settings,
///   library selection, logins), and "Who's reading?" never shows;
/// - servers (and the login whoever added them used) live in the
///   user-independent keychain, so they're added once for everyone.
///
/// In the simulator, on a single-user Apple TV, or without the entitlement
/// this is false and in-app profiles are the fallback: one set of profiles
/// with "Who's reading?" at launch.
///
/// The tvOS `DeviceUserIdentity`, and the only use of `TVUserManager`.
struct AppleTVUserIdentity: DeviceUserIdentity {
    let separatesAppDataPerUser = TVUserManager().shouldStorePreferencesForCurrentUser
}

extension AppModel {
    /// Activates a profile chosen on "Who's reading?". When running as the
    /// current Apple TV user (with older state holding several profiles)
    /// the choice is remembered, since the picker doesn't show then.
    func pickProfile(_ id: UUID) {
        switchProfile(id)
        if perAppleTVUser { update { $0.pickProfile(id, remember: true) } }
        isPickingProfile = false
    }

    /// True when the profile is using a login another Apple TV user entered.
    func usesSharedLogin(for server: ServerConfig) -> Bool {
        guard let store = secrets as? SharedFallbackSecretStore else { return false }
        return !store.hasOwnCredential(profile: loginProfileID, server: server.id)
            && store.credential(profile: loginProfileID, server: server.id) != nil
    }

    /// Pulls in servers other Apple TV users added or removed, then writes
    /// this user's list back, and keeps them in step from then on.
    func adoptSharedServers() {
        guard let shared = sharedServers else { return }
        var directory = shared.load() ?? SharedServerDirectory()
        var removed: [UUID] = []
        update { removed = $0.adopt(directory) }
        let profiles = state.profiles.map(\.id)
        for id in removed { secrets.removeCredentials(server: id, profiles: profiles) }
        // Servers this user had before sharing was on join the directory,
        // with the active profile's login as the shared one.
        directory.upsert(state.servers)
        if let store = secrets as? SharedFallbackSecretStore {
            for server in state.servers where directory.credential(for: server.id) == nil {
                directory.offerCredential(store.local.credential(profile: activeProfile.id, server: server.id),
                                          for: server.id)
            }
        }
        if directory != shared.load() { shared.save(directory) }

        stateObservers.append { old, new in
            guard old.servers != new.servers, var d = shared.load() else { return }
            d.record(before: old.servers, after: new.servers)
            shared.save(d)
        }
    }
}
