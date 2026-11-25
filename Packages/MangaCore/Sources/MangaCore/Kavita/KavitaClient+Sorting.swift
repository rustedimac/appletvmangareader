import Foundation

extension KavitaFilterV2.Sort {
    /// Kavita's `SortField.ReadProgress`: most recently read first when descending.
    static let readProgress = 7
}

extension KavitaClient {
    /// Kavita sorts library grids on the server (FilterV2 `sortOptions`).
    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary> {
        var filter = KavitaFilterV2()
        filter.statements = [.init(comparison: KavitaFilterV2.Comparison.equal,
                                   field: KavitaFilterV2.Field.libraries,
                                   value: category.id)]
        filter.sortOptions = Self.sortOptions(sort)
        let items: [KavitaSeriesDTO] = try await withAuth {
            try await $0.post("api/Series/v2",
                              query: ["libraryId": category.id, "pageNumber": String(page), "pageSize": String(pageSize)],
                              body: filter)
        }
        return Paged(items: items.map(summary), hasMore: items.count >= pageSize)
    }

    static func sortOptions(_ sort: LibrarySort) -> KavitaFilterV2.SortOptions {
        switch sort {
        case .titleAscending: return .init(sortField: KavitaFilterV2.Sort.sortName, isAscending: true)
        case .titleDescending: return .init(sortField: KavitaFilterV2.Sort.sortName, isAscending: false)
        case .recentlyAdded: return .init(sortField: KavitaFilterV2.Sort.createdDate, isAscending: false)
        case .recentlyUpdated: return .init(sortField: KavitaFilterV2.Sort.lastChapterAdded, isAscending: false)
        case .recentlyRead: return .init(sortField: KavitaFilterV2.Sort.readProgress, isAscending: false)
        }
    }
}
