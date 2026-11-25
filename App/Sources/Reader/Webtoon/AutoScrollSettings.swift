import Foundation
import MangaCore

extension AppModel {
    /// The active profile's webtoon auto-scroll speed level.
    var autoScrollLevel: Int { state.autoScrollLevel(profile: activeProfile.id) }

    func setAutoScrollLevel(_ level: Int) {
        let profile = activeProfile.id
        update { $0.setAutoScrollLevel(level, profile: profile) }
    }
}
