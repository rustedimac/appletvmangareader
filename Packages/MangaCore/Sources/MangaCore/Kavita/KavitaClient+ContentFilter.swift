import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A genre or tag from `api/Metadata/genres` / `api/Metadata/tags`.
struct KavitaMetadataItemDTO: Decodable {
    var id: Int
    var title: String
}

extension KavitaFilterV2.Field {
    static let ageRating = 4
    static let tags = 6
}

extension KavitaFilterV2.Comparison {
    static let lessThanEqual = 4
}

extension KavitaFilterV2 {
    /// 0 = Or, 1 = And.
    static let or = 0
}

extension KavitaClient {
    /// Series fetched per request when collecting hidden ids.
    static let hiddenPageSize = 500
    /// Stops after this many pages (100,000 series) in case paging misbehaves.
    static let hiddenMaxPages = 200

    public func contentFacets() async throws -> ContentFacets {
        try await withAuth { client in
            async let genres: [KavitaMetadataItemDTO] = client.get("api/Metadata/genres")
            async let tags: [KavitaMetadataItemDTO] = client.get("api/Metadata/tags")
            return ContentFacets(genres: try await genres.map(\.title), tags: try await tags.map(\.title),
                                 supportsAgeRating: true)
        }
    }

    /// Asks Kavita for every series matching any hidden genre, tag or age
    /// rating (one FilterV2 query with "or"), so the filter works the same
    /// way Kavita's own smart filters do, and returns their ids.
    public func hiddenSeriesIDs(for filter: ContentFilter) async throws -> Set<String> {
        guard filter.isActive else { return [] }
        let statements = try await hiddenStatements(for: filter)
        guard !statements.isEmpty else { return [] }
        var body = KavitaFilterV2()
        body.statements = statements
        body.combination = KavitaFilterV2.or
        var ids = Set<String>()
        for page in 1...Self.hiddenMaxPages {
            let items: [KavitaSeriesDTO] = try await withAuth {
                try await $0.post("api/Series/v2",
                                  query: ["pageNumber": String(page), "pageSize": String(Self.hiddenPageSize)],
                                  body: body)
            }
            ids.formUnion(items.map { String($0.id) })
            if items.count < Self.hiddenPageSize { break }
        }
        return ids
    }

    /// FilterV2 statements for the filter, mapping genre and tag names to
    /// Kavita's ids. Names Kavita doesn't have are skipped.
    func hiddenStatements(for filter: ContentFilter) async throws -> [KavitaFilterV2.Statement] {
        var statements: [KavitaFilterV2.Statement] = []
        func ids(_ items: [KavitaMetadataItemDTO], matching keys: Set<String>) -> String? {
            let matched = items.filter { keys.contains(ContentFilter.normalize($0.title)) }.map(\.id)
            return matched.isEmpty ? nil : Array(Set(matched)).sorted().map(String.init).joined(separator: ",")
        }
        if !filter.hiddenGenres.isEmpty {
            let genres: [KavitaMetadataItemDTO] = try await withAuth { try await $0.get("api/Metadata/genres") }
            if let value = ids(genres, matching: filter.hiddenGenreKeys) {
                statements.append(.init(comparison: KavitaFilterV2.Comparison.contains,
                                        field: KavitaFilterV2.Field.genres, value: value))
            }
        }
        if !filter.hiddenTags.isEmpty {
            let tags: [KavitaMetadataItemDTO] = try await withAuth { try await $0.get("api/Metadata/tags") }
            if let value = ids(tags, matching: filter.hiddenTagKeys) {
                statements.append(.init(comparison: KavitaFilterV2.Comparison.contains,
                                        field: KavitaFilterV2.Field.tags, value: value))
            }
        }
        if let max = filter.maxAgeRating {
            statements.append(.init(comparison: KavitaFilterV2.Comparison.greaterThan,
                                    field: KavitaFilterV2.Field.ageRating, value: String(max.rawValue)))
            if filter.hideUnrated {
                statements.append(.init(comparison: KavitaFilterV2.Comparison.lessThanEqual,
                                        field: KavitaFilterV2.Field.ageRating,
                                        value: String(AgeRating.unratedCeiling.rawValue)))
            }
        }
        return statements
    }
}
