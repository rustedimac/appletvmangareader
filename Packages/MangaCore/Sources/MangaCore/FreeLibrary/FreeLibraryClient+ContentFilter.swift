import Foundation

/// The curated catalog lists genres per series, so genre filters apply here
/// too. It has no tags or age ratings; everything in it is public domain or
/// CC-licensed and picked to be all-ages.
extension FreeLibraryClient {
    public func contentFacets() async throws -> ContentFacets {
        var seen = Set<String>()
        var genres: [String] = []
        for g in (await catalog()).series.flatMap({ $0.genres ?? [] }) {
            if seen.insert(ContentFilter.normalize(g)).inserted { genres.append(g) }
        }
        return ContentFacets(genres: genres.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    public func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        guard !filter.hiddenGenres.isEmpty else { return [] }
        return Set((await catalog()).series
            .filter { filter.hides(genres: $0.genres ?? [], supportsAgeRating: false) }
            .map(\.id))
    }
}
