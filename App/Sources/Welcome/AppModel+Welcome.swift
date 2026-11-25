import Foundation
import MangaCore

extension AppModel {
    /// Whether the first-run welcome replaces the tabs for the active
    /// profile (see `Welcome.shouldShow`). UI tests only see it with
    /// `-welcome`, so the rest of the suite starts on the tabs as before.
    var showsWelcome: Bool {
        if UITestingSeed.isUITesting && !UITestingSeed.arguments.contains("-welcome") { return false }
        return Welcome.shouldShow(state, profile: activeProfile.id)
    }

    /// "Start Reading": adds the Free Library with these collections for
    /// the active profile and goes to Home.
    func finishWelcome(collections: Set<String>, allCollections: Set<String>) {
        let profile = activeProfile.id
        update { $0.finishWelcome(collections: collections, allCollections: allCollections, profile: profile) }
        resetClients()
    }
}
