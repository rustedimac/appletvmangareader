import Foundation

/// Which PIN-protected profiles are unlocked right now, and the wrong-PIN
/// throttle. Lives in memory only: everything locks again when the app goes
/// to the background or the profile changes.
///
/// A profile with a PIN asks for it to change its content settings, PIN,
/// profile details, and servers while it's active. Opening it asks too when
/// `AppState.requiresPINToOpen` is on, so a parent can lock a child's
/// settings without locking the child out.
public struct ProfileLocks: Sendable {
    public enum Result: Equatable, Sendable {
        /// The PIN matched this profile, which is now unlocked.
        case unlocked(UUID)
        /// Wrong PIN. `triesLeft` before a lockout starts (0 when locked).
        case wrong(triesLeft: Int)
        /// Too many wrong PINs; try again in this many seconds.
        case lockedOut(seconds: Int)
    }

    public private(set) var unlocked: Set<UUID> = []
    /// One throttle for every profile, so guessing can't be spread out.
    public private(set) var limiter = PINAttemptLimiter()

    public init() {}

    /// True when `profile` has no PIN or it was entered this session.
    public func isUnlocked(_ profile: UUID, store: PINStore) -> Bool {
        unlocked.contains(profile) || !store.hasPIN(profile: profile)
    }

    /// Checks `pin` against each of `candidates` (normally one profile; any
    /// PIN-protected profile for adding a new profile).
    public mutating func attempt(_ pin: String, candidates: [UUID], store: PINStore,
                                 now: Date = Date()) -> Result {
        if let wait = limiter.lockoutRemaining(now: now) { return .lockedOut(seconds: Int(wait.rounded(.up))) }
        if let match = candidates.first(where: { store.verify(pin, profile: $0) }) {
            limiter.recordSuccess()
            unlocked.insert(match)
            return .unlocked(match)
        }
        limiter.recordFailure(now: now)
        if let wait = limiter.lockoutRemaining(now: now) { return .lockedOut(seconds: Int(wait.rounded(.up))) }
        return .wrong(triesLeft: max(0, PINAttemptLimiter.freeAttempts - limiter.failures))
    }

    /// Marks a profile unlocked without a PIN, e.g. right after setting one.
    public mutating func markUnlocked(_ profile: UUID) {
        unlocked.insert(profile)
    }

    public mutating func lock(_ profile: UUID) {
        unlocked.remove(profile)
    }

    public mutating func lockAll() {
        unlocked.removeAll()
    }
}
