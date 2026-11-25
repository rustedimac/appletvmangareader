import Foundation

/// Decides which profile opens at launch.
///
/// When the app runs as the current Apple TV user (tvOS user management),
/// the Apple TV user *is* the profile: the system gives each user their own
/// copy of this state, which normally holds one profile, so it opens
/// straight away and "Who's reading?" never shows. If that state has more
/// than one profile (made before user management was on), the one picked
/// last opens.
///
/// Without Apple TV users (simulator, no entitlement, or a single-user
/// Apple TV) in-app profiles are the fallback: the picker shows whenever
/// there's more than one.
public struct ProfileLaunch: Equatable, Sendable {
    public var profileID: UUID?
    public var showsPicker: Bool

    public init(profileID: UUID?, showsPicker: Bool) {
        self.profileID = profileID
        self.showsPicker = showsPicker
    }

    public static func decide(_ state: AppState, perSystemUser: Bool) -> ProfileLaunch {
        if perSystemUser {
            let remembered = state.rememberedProfileID.flatMap { id in state.profiles.first { $0.id == id }?.id }
            return ProfileLaunch(profileID: remembered ?? state.activeProfile?.id, showsPicker: false)
        }
        return ProfileLaunch(profileID: state.activeProfile?.id, showsPicker: state.profiles.count > 1)
    }
}

public extension AppState {
    /// Activates a profile and, when the app runs as the current Apple TV
    /// user, remembers it for next launch.
    mutating func pickProfile(_ id: UUID, remember: Bool) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        if remember { rememberedProfileID = id }
    }
}
