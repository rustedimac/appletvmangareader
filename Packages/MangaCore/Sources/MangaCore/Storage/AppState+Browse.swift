import Foundation

/// Per-profile browsing preferences (`BrowsePreferences`): Home layout,
/// per-library sort / reading style / grid order, poster size, Continue
/// Reading dismissals and the Caught Up row.
public extension AppState {
    func browse(profile: UUID) -> BrowsePreferences {
        profileData[profile.uuidString]?.browse ?? BrowsePreferences()
    }

    mutating func updateBrowse(profile: UUID, _ body: (inout BrowsePreferences) -> Void) {
        mutateData(profile) { data in
            var prefs = data.browse ?? BrowsePreferences()
            body(&prefs)
            data.browse = prefs.isDefault ? nil : prefs
        }
    }

    // MARK: Reader settings by library

    /// The settings a series opens with when it has none of its own: the
    /// profile default, with its library's reading style applied.
    func defaultReaderSettings(for series: SeriesSummary, profile: UUID) -> ReaderSettings {
        let base = (profileData[profile.uuidString]?.defaultReaderSettings ?? .default).normalizedPairing
        guard let style = browse(profile: profile).readingStyle(for: series) else { return base }
        return style.apply(to: base)
    }

    /// The series' own settings, else its library default.
    func readerSettings(for series: SeriesSummary, profile: UUID) -> ReaderSettings {
        profileData[profile.uuidString]?.readerOverrides[series.ref.storageKey]?.normalizedPairing
            ?? defaultReaderSettings(for: series, profile: profile)
    }

    // MARK: Continue Reading

    /// Continue Reading without the series the profile removed from it
    /// (until it reads them again).
    func filterContinueReading(_ series: [SeriesSummary], profile: UUID) -> [SeriesSummary] {
        browse(profile: profile).filterContinueReading(series) { progress($0, profile: profile)?.updatedAt }
    }

    // MARK: Caught Up

    /// Caught Up series from libraries/categories the profile imports,
    /// newest first.
    func visibleCaughtUp(profile: UUID) -> [CaughtUpEntry] {
        browse(profile: profile).caughtUp.filter {
            serverSettings(profile: profile, server: $0.series.ref.serverID).includes($0.series)
                && server($0.series.ref.serverID) != nil
        }
    }
}
