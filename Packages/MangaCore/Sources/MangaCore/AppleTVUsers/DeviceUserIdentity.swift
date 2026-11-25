import Foundation

/// Who uses the device, as the platform sees it. The only platform-specific
/// piece of the profile system: tvOS supplies `AppleTVUserIdentity` (in the
/// app target, the one place `TVUserManager` is used); an iPhone or Mac app
/// would supply its own, typically `SingleUserDevice`.
///
/// Everything a profile owns (favorites, progress, reader settings, library
/// selection, logins) lives in platform-neutral `AppState` / `SecretStore`
/// types, so another platform, or later an iCloud sync, can reuse them.
public protocol DeviceUserIdentity: Sendable {
    /// True when the OS keeps separate app data for each signed-in user, so
    /// the saved state already belongs to one person: one profile per user,
    /// no "Who's reading?", and servers shared through `SharedServerStore`.
    var separatesAppDataPerUser: Bool { get }
}

/// One person per device (or one shared set of data): in-app profiles with
/// "Who's reading?" are how people are told apart.
public struct SingleUserDevice: DeviceUserIdentity {
    public init() {}
    public var separatesAppDataPerUser: Bool { false }
}

/// A fixed answer, for tests.
public struct FixedDeviceUserIdentity: DeviceUserIdentity {
    public let separatesAppDataPerUser: Bool
    public init(separatesAppDataPerUser: Bool) { self.separatesAppDataPerUser = separatesAppDataPerUser }
}
