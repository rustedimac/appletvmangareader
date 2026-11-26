import Foundation

extension KavitaFilterV2.Sort {
    /// Kavita's `SortField.ReadProgress`: most recently read first when descending.
    static let readProgress = 7
}

extension KavitaClient {
    /// Kavita sorts library grids on the server (FilterV2 `sortOptions`).
    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort) async throws -> Paged<SeriesSummary> {
        try await series(in: category, page: page, pageSize: pageSize, sort: sort, filter: .empty)
    }

    /// Kavita filters on the server too (FilterV2 statements, combined with And).
    public var libraryFilterSupport: LibraryFilterSupport { .all }

    public func series(in category: MangaCategory, page: Int, pageSize: Int, sort: LibrarySort,
                       filter libraryFilter: LibraryFilter) async throws -> Paged<SeriesSummary> {
        var filter = KavitaFilterV2()
        filter.statements = [.init(comparison: KavitaFilterV2.Comparison.equal,
                                   field: KavitaFilterV2.Field.libraries,
                                   value: category.id)]
        let wanted = libraryFilter.limited(to: libraryFilterSupport)
        var genreIDs: [Int] = []
        if !wanted.genres.isEmpty {
            genreIDs = Self.genreIDs(for: wanted.genres, in: try await genreTags(in: category))
            // None of the picked genres is in this library: nothing matches.
            if genreIDs.isEmpty { return Paged(items: [], hasMore: false) }
        }
        filter.statements += Self.statements(for: wanted, genreIDs: genreIDs)
        filter.sortOptions = Self.sortOptions(sort)
        let items: [KavitaSeriesDTO] = try await withAuth {
            try await $0.post("api/Series/v2",
                              query: ["libraryId": category.id, "pageNumber": String(page), "pageSize": String(pageSize)],
                              body: filter)
        }
        return Paged(items: items.map(summary), hasMore: items.count >= pageSize)
    }

    public func filterGenres(in category: MangaCategory) async throws -> [String] {
        LibraryFilter.genreList(try await genreTags(in: category).map(\.title))
    }

    func genreTags(in category: MangaCategory) async throws -> [KavitaGenreDTO] {
        try await withAuth { try await $0.get("api/Metadata/genres", query: ["libraryIds": category.id]) }
    }

    /// Ids of the tags whose names match `names` (case and accents ignored).
    static func genreIDs(for names: Set<String>, in tags: [KavitaGenreDTO]) -> [Int] {
        let wanted = Set(names.map(LibraryFilter.fold))
        return tags.filter { wanted.contains(LibraryFilter.fold($0.title)) }.compactMap(\.id).sorted()
    }

    /// FilterV2 statements for a library filter. Contains is an Or within
    /// one statement; statements are combined with And. ReadProgress is
    /// the percentage of pages read (0...100).
    static func statements(for filter: LibraryFilter, genreIDs: [Int]) -> [KavitaFilterV2.Statement] {
        typealias F = KavitaFilterV2.Field
        typealias C = KavitaFilterV2.Comparison
        var out: [KavitaFilterV2.Statement] = []
        if !filter.statuses.isEmpty {
            let values = filter.statuses.flatMap(\.kavitaValues).sorted()
            out.append(.init(comparison: C.contains, field: F.publicationStatus,
                             value: values.map(String.init).joined(separator: ",")))
        }
        switch filter.readProgress {
        case .any: break
        case .unread: out.append(.init(comparison: C.equal, field: F.readProgress, value: "0"))
        case .inProgress:
            out.append(.init(comparison: C.greaterThan, field: F.readProgress, value: "0"))
            out.append(.init(comparison: C.lessThan, field: F.readProgress, value: "100"))
        case .unfinished: out.append(.init(comparison: C.lessThan, field: F.readProgress, value: "100"))
        case .read: out.append(.init(comparison: C.equal, field: F.readProgress, value: "100"))
        }
        if !genreIDs.isEmpty {
            out.append(.init(comparison: C.contains, field: F.genres,
                             value: genreIDs.map(String.init).joined(separator: ",")))
        }
        return out
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
