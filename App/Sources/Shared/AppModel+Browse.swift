import Foundation
import MangaCore

/// Browsing preferences for the active profile (see `BrowsePreferences`).
extension AppModel {
    var browsePreferences: BrowsePreferences { state.browse(profile: activeProfile.id) }

    func updateBrowse(_ body: (inout BrowsePreferences) -> Void) {
        let profile = activeProfile.id
        update { $0.updateBrowse(profile: profile, body) }
    }

    var homeLayout: HomeLayout { browsePreferences.home }
    var gridDensity: GridDensity { browsePreferences.gridDensity }
    var posterCaption: PosterCaption { browsePreferences.posterCaption }
    var appTheme: AppTheme { browsePreferences.theme }

    // MARK: Libraries

    func libraryOptions(_ server: ServerConfig, _ category: MangaCategory) -> LibraryOptions {
        browsePreferences.options(for: LibraryKey(serverID: server.id, categoryID: category.id))
    }

    func setLibraryOptions(_ options: LibraryOptions, _ server: ServerConfig, _ category: MangaCategory) {
        updateBrowse { $0.setOptions(options, for: LibraryKey(serverID: server.id, categoryID: category.id)) }
    }

    // MARK: Reader settings by library

    /// The series' own reader settings, else its library's style on top of
    /// the profile default.
    func readerSettings(for series: SeriesSummary) -> ReaderSettings {
        state.readerSettings(for: series, profile: activeProfile.id)
    }

    /// What "Reset to Default" in the reader goes back to.
    func libraryDefaultReaderSettings(for series: SeriesSummary) -> ReaderSettings {
        state.defaultReaderSettings(for: series, profile: activeProfile.id)
    }

    // MARK: Continue Reading

    func filterContinueReading(_ series: [SeriesSummary]) -> [SeriesSummary] {
        state.filterContinueReading(series, profile: activeProfile.id)
    }

    func removeFromContinueReading(_ ref: SeriesRef) {
        updateBrowse { $0.dismissFromContinueReading(ref, at: Date()) }
    }

    // MARK: Caught Up

    var caughtUpSeries: [SeriesSummary] { state.visibleCaughtUp(profile: activeProfile.id).map(\.series) }

    /// Called whenever series detail loads, with the summary the user
    /// navigated with. Saves only when the Caught Up row changes.
    func noteSeriesDetail(_ detail: SeriesDetail, summary: SeriesSummary) {
        seriesCounts.record(SeriesCount(chapters: detail.chapters, seriesFormat: detail.summary.format ?? summary.format),
                            for: summary.ref)
        var prefs = browsePreferences
        let before = prefs.caughtUp
        prefs.noteCaughtUp(detail, summary: summary, now: Date())
        guard prefs.caughtUp != before else { return }
        let caughtUp = prefs.caughtUp
        updateBrowse { $0.caughtUp = caughtUp }
    }

    /// Drops Caught Up series that Home's feeds show with new chapters.
    func pruneCaughtUp(seenIn feeds: [SeriesSummary]) {
        var prefs = browsePreferences
        guard prefs.pruneCaughtUp(seenIn: feeds) else { return }
        let caughtUp = prefs.caughtUp
        updateBrowse { $0.caughtUp = caughtUp }
    }
}
