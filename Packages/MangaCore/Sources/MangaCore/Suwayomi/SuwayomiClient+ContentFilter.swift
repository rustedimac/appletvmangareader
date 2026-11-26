import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Suwayomi has genres (from the source) but no tags or age ratings, so the
/// filter matches on `MangaType.genre` alone.
extension SuwayomiClient {
    struct GenreNode: Decodable {
        var id: Int
        var genre: [String]?
    }

    /// Every library manga's genres. One small query; a library of a
    /// thousand manga is a few tens of kilobytes.
    func libraryGenres() async throws -> [GenreNode] {
        struct Response: Decodable { var mangas: Nodes<GenreNode> }
        let r: Response = try await graphQL("query { mangas(condition: {inLibrary: true}) { nodes { id genre } } }")
        return r.mangas.nodes
    }

    public func contentFacets() async throws -> ContentFacets {
        var seen = Set<String>()
        var genres: [String] = []
        for node in try await libraryGenres() {
            for g in node.genre ?? [] {
                let name = g.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, seen.insert(ContentFilter.normalize(name)).inserted { genres.append(name) }
            }
        }
        return ContentFacets(genres: genres.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                             tags: [], supportsAgeRating: false)
    }

    public func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        // Only genres apply here; tags and age limits have nothing to match.
        guard !filter.hiddenGenres.isEmpty else { return [] }
        return Set(try await libraryGenres()
            .filter { filter.hides(genres: $0.genre ?? [], supportsAgeRating: false) }
            .map { String($0.id) })
    }
}
