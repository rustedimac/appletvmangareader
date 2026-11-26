import Foundation
import MangaCore

/// Guest sessions: a visitor reads from this Apple TV's servers without a
/// profile of their own. See `GuestSession` and docs/ARCHITECTURE.md
/// ("Guest").
///
/// While a guest reads, `state` is the guest's in-memory state and the
/// saved state waits in `ownerState`. `update` doesn't save, sync or
/// publish anything then, and `syncsProgress` is false for every server,
/// so the owner's progress, favorites, bookmarks, settings and servers stay
/// exactly as they were. Ending the session (or quitting the app) throws
/// the guest's reading away.
extension AppModel {
    var isGuest: Bool { guestSession != nil }

    /// Starts a guest session that reads with the active profile's logins.
    func startGuestSession() {
        guard guestSession == nil else { return }
        let session = GuestSession(hostProfileID: activeProfile.id)
        let owner = state
        ownerState = owner
        setGuestSession(session)
        // Not saved: `update` skips saving once the session is set.
        update { $0 = session.makeState(from: owner) }
        guestBookPositions = BookPositionStore(backing: InMemoryKeyValueStore())
        resetClients()
        isPickingProfile = false
    }

    /// Ends the guest session and brings back the saved state. With in-app
    /// profiles (and more than one of them) "Who's reading?" shows next.
    func endGuestSession(showPicker: Bool = true) {
        guard isGuest, let owner = ownerState else { return }
        setGuestSession(nil)
        ownerState = nil
        guestBookPositions = BookPositionStore(backing: InMemoryKeyValueStore())
        update { $0 = owner }
        resetClients()
        isPickingProfile = showPicker && !perAppleTVUser && state.profiles.count > 1
        // The owner's queued pushes waited while the guest read.
        Task { await retryPendingProgressNow() }
    }

    /// The state saved on this device, whoever is reading. iCloud sync,
    /// backups and the Top Shelf use it, never a guest's state.
    var savedState: AppState { ownerState ?? state }
}
