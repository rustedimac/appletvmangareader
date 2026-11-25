import Foundation

/// A series the profile is partway through, for Continue Reading.
public struct ContinueReadingEntry: Hashable, Sendable {
    public var series: SeriesSummary
    public var progress: SeriesProgress
}

public extension AppState {
    /// How many read series' titles and covers are kept per profile.
    static let recentSeriesLimit = 40

    /// Remembers a series' title and cover for this profile, so Continue
    /// Reading can show it later. Keeps the most recently read
    /// `recentSeriesLimit` series that have progress.
    mutating func noteRecentSeries(_ series: SeriesSummary, profile: UUID) {
        mutateData(profile) { data in
            var recent = data.recentSeries ?? [:]
            if let old = recent[series.ref.storageKey] {
                // Keep fields a thinner summary (e.g. from a deep link) lacks.
                var merged = series
                merged.coverURL = series.coverURL ?? old.coverURL
                merged.libraryID = series.libraryID ?? old.libraryID
                merged.unreadCount = series.unreadCount ?? old.unreadCount
                recent[series.ref.storageKey] = merged
            } else {
                recent[series.ref.storageKey] = series
            }
            if recent.count > Self.recentSeriesLimit {
                let keep = recent.keys
                    .sorted { (data.progress[$0]?.updatedAt ?? .distantPast) > (data.progress[$1]?.updatedAt ?? .distantPast) }
                    .prefix(Self.recentSeriesLimit)
                    .map { $0 } + [series.ref.storageKey]
                recent = recent.filter { keep.contains($0.key) }
            }
            data.recentSeries = recent
        }
    }

    /// The best summary this profile has for a series: favorites first
    /// (they carry library ids), then recently read.
    func knownSummary(_ ref: SeriesRef, profile: UUID) -> SeriesSummary? {
        let data = profileData[profile.uuidString]
        return data?.favorites.first { $0.series.ref == ref }?.series
            ?? data?.recentSeries?[ref.storageKey]
    }

    /// Series the profile has started, most recent first. Skips series
    /// without a saved title, on servers that are gone, or whose progress
    /// was reset (no open chapter).
    func continueReading(profile: UUID, limit: Int = 10) -> [ContinueReadingEntry] {
        guard let data = profileData[profile.uuidString] else { return [] }
        let serverIDs = Set(servers.map(\.id))
        return data.progress.compactMap { key, progress -> ContinueReadingEntry? in
            guard !progress.chapterID.isEmpty, let series = data.recentSeries?[key],
                  serverIDs.contains(series.ref.serverID) else { return nil }
            return ContinueReadingEntry(series: series, progress: progress)
        }
        .sorted { $0.progress.updatedAt > $1.progress.updatedAt }
        .prefix(limit)
        .map { $0 }
    }

    /// Favorites for the Top Shelf: those with unread chapters first (most
    /// unread first), then the rest, newest favorite first.
    func favoritesForTopShelf(profile: UUID, limit: Int = 12) -> [Favorite] {
        let all = favorites(profile: profile)
        let withNew = all.filter { $0.newChapterCount > 0 }
            .sorted { $0.newChapterCount > $1.newChapterCount }
        let rest = all.filter { $0.newChapterCount == 0 }
        return Array((withNew + rest).prefix(limit))
    }
}

public extension Favorite {
    /// Unread chapters for the Top Shelf: the last refresh's count
    /// (`unreadChapters`), else what the server reported in the summary.
    var newChapterCount: Int { unreadChapters ?? series.unreadCount ?? 0 }
}
