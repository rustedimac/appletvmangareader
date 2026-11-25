import Foundation
import MangaCore

extension AppModel {
    /// In-section positions for books (see `BookPositionStore`). In memory
    /// for UI tests, like the rest of their state.
    static let bookPositions: BookPositionStore = {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return BookPositionStore(backing: InMemoryKeyValueStore())
        }
        return BookPositionStore(backing: UserDefaultsStore())
    }()

    /// The active profile's book reader settings.
    var bookSettings: BookSettings {
        state.bookSettings(profile: activeProfile.id)
    }

    func setBookSettings(_ settings: BookSettings) {
        let profile = activeProfile.id
        update { $0.setBookSettings(settings, profile: profile) }
    }
}
