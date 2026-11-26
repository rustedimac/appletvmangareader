import Foundation

/// The first-run welcome: shown instead of Home when a profile has nothing
/// to read yet, so it can pick Free Library collections, add a server or
/// restore a backup. See docs/FREE_LIBRARY.md ("First-run welcome").
///
/// It never shows when any server of the user's own exists, and it doesn't
/// come back once a profile has started reading unless every library is
/// gone again.
public enum Welcome {
    /// Collections ticked when the picker opens: the picture-first ones.
    /// The rest (illustrated books, pulp magazines) are a tick away.
    public static let suggestedCollections: Set<String> = ["comics", "webcomics"]

    /// Whether `profile` should see the welcome instead of Home.
    public static func shouldShow(_ state: AppState, profile: UUID) -> Bool {
        // Someone with a server of their own is never stopped here.
        if state.servers.contains(where: { $0.kind != .freeLibrary }) { return false }
        // Nothing at all to read (say, the Free Library was removed and no
        // server was added): always offer the way back.
        guard state.hasFreeLibrary else { return true }
        guard let data = state.profileData[profile.uuidString] else { return true }
        if data.welcomeCompleted == true { return false }
        // Profiles from before the welcome existed that already used the
        // Free Library have made their choice.
        let picked = data.serverSettings[FreeLibrary.serverID.uuidString]?.selectedCategoryIDs != nil
        return !(picked || !data.favorites.isEmpty || !data.progress.isEmpty || !data.bookmarks.isEmpty)
    }

    /// One row of the picker.
    public struct Choice: Identifiable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var summary: String
        /// "4 series" or "2 series · 144 issues".
        public var detail: String
    }

    /// The catalog's collections that have something in them, in order.
    public static func choices(from catalog: FreeLibraryCatalog) -> [Choice] {
        catalog.collections.compactMap { entry -> Choice? in
            let series = catalog.series.filter { $0.collection == entry.id }
            guard !series.isEmpty else { return nil }
            var detail = series.count == 1 ? "1 series" : "\(series.count) series"
            let issues = series.reduce(0) { $0 + ($1.chapters?.count ?? 0) }
            if series.contains(where: { ($0.chapters?.count ?? 0) > 2 }) {
                detail += " · \(issues) issues"
            } else if series.contains(where: { $0.source == .pepperCarrot }) {
                detail += " · new episodes as they come out"
            }
            return Choice(id: entry.id, name: entry.name, summary: entry.summary ?? "", detail: detail)
        }
    }

    /// The ticks to start from: what this profile already picked if it ever
    /// did, otherwise the suggested set (limited to what the catalog has).
    public static func initialSelection(_ state: AppState, profile: UUID, choices: [Choice]) -> Set<String> {
        let ids = Set(choices.map(\.id))
        if state.hasFreeLibrary,
           let saved = state.selectedCategories(profile: profile, server: FreeLibrary.serverID) {
            return saved.intersection(ids)
        }
        let suggested = suggestedCollections.intersection(ids)
        return suggested.isEmpty ? ids : suggested
    }
}

public extension AppState {
    /// "Start Reading" on the welcome: adds the Free Library (back) with the
    /// ticked collections for `profile`, and marks the welcome done. Ticking
    /// every collection saves "all", so collections added to the catalog
    /// later show up too. An empty set only marks the welcome done.
    mutating func finishWelcome(collections: Set<String>, allCollections: Set<String>, profile: UUID) {
        if !collections.isEmpty {
            restoreFreeLibrary()
            let all = !allCollections.isEmpty && allCollections.isSubset(of: collections)
            setSelectedCategories(all ? nil : collections, profile: profile, server: FreeLibrary.serverID)
        }
        var data = profileData[profile.uuidString] ?? ProfileData()
        data.welcomeCompleted = true
        profileData[profile.uuidString] = data
    }
}
