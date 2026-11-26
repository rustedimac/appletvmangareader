import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Kavita reading lists, collections and smart filters, read-only.
//
// - Reading lists: `POST api/ReadingList/lists` (the user's own plus
//   promoted ones), items from `GET api/ReadingList/items`.
// - Collections: `GET api/Collection` (own plus promoted), series from
//   `GET api/Series/series-by-collection`.
// - Smart filters: `GET api/filter`. Each holds an encoded series filter;
//   `POST api/filter/decode` turns it into FilterV2, which goes to
//   `POST api/Series/all-v2` as is.
//
// Kavita applies the user's library access and age rating to all of
// these. The app's own library pick (`categoryScope`) is applied on top,
// after each page, so a list can show fewer items than the server has.

struct KavitaReadingListDTO: Decodable {
    let id: Int
    let title: String?
    let summary: String?
    let promoted: Bool?
    let itemCount: Int?
}

struct KavitaReadingListItemDTO: Decodable {
    struct Chapter: Decodable {
        let pages: Int?
        let range: String?
        let titleName: String?
    }

    let id: Int
    let order: Int?
    let chapterId: Int
    let seriesId: Int
    let seriesName: String?
    let seriesFormat: Int?
    let pagesRead: Int?
    let pagesTotal: Int?
    let chapterNumber: String?
    let volumeNumber: String?
    let chapterTitleName: String?
    let volumeId: Int?
    let libraryId: Int?
    let title: String?
    let chapter: Chapter?
}

struct KavitaCollectionDTO: Decodable {
    let id: Int
    let title: String?
    let summary: String?
    let promoted: Bool?
    let itemCount: Int?
}

struct KavitaSmartFilterDTO: Decodable {
    let id: Int
    let name: String?
    let filter: String?
    /// 0 = series. Missing on servers before 0.9 (series only).
    let entityType: Int?
}

struct KavitaDecodeFilterDTO: Encodable {
    let encodedFilter: String
}

/// FilterV2 as `api/filter/decode` returns it, sent back unchanged.
struct KavitaDecodedFilter: Codable {
    struct Statement: Codable {
        var comparison: Int
        var field: Int
        var value: String
    }

    struct SortOptions: Codable {
        var sortField: Int
        var isAscending: Bool
    }

    var id: Int?
    var name: String?
    var statements: [Statement]?
    var combination: Int?
    var sortOptions: SortOptions?
    var limitTo: Int?

    /// And, or no statements to combine (Kavita's default is And).
    var isAnd: Bool { (statements ?? []).count < 2 || (combination ?? 1) == 1 }
}

extension KavitaClient {
    public var collectionSupport: ServerCollectionSupport { .all }

    public func collections(_ kind: ServerCollectionKind) async throws -> [ServerCollection] {
        switch kind {
        case .readingList:
            let lists: [KavitaReadingListDTO] = try await withAuth {
                try await $0.post("api/ReadingList/lists",
                                  query: ["includePromoted": "true", "sortByLastModified": "false",
                                          "pageNumber": "1", "pageSize": "0"],
                                  body: EmptyBody())
            }
            return lists.map {
                ServerCollection(serverID: config.id, kind: .readingList, collectionID: String($0.id),
                                 title: Self.title($0.title), summary: Self.text($0.summary), itemCount: $0.itemCount,
                                 promoted: $0.promoted ?? false, coverURL: readingListCoverURL($0.id))
            }
        case .collection:
            let tags: [KavitaCollectionDTO] = try await withAuth {
                try await $0.get("api/Collection", query: ["ownedOnly": "false"])
            }
            return tags.map {
                ServerCollection(serverID: config.id, kind: .collection, collectionID: String($0.id),
                                 title: Self.title($0.title), summary: Self.text($0.summary), itemCount: $0.itemCount,
                                 promoted: $0.promoted ?? false, coverURL: collectionCoverURL($0.id))
            }
        case .smartFilter:
            let filters: [KavitaSmartFilterDTO] = try await withAuth { try await $0.get("api/filter") }
            return filters
                .filter { ($0.entityType ?? 0) == 0 && !($0.filter ?? "").isEmpty }
                .map {
                    ServerCollection(serverID: config.id, kind: .smartFilter, collectionID: String($0.id),
                                     title: Self.title($0.name), payload: $0.filter)
                }
        }
    }

    /// With every library picked, pages come from the server. With only
    /// some picked, a collection loads whole on page 1 and is narrowed
    /// here, since Kavita can't filter it by library; a smart filter whose
    /// statements are combined with And gets a library statement added
    /// instead, and an Or filter loads whole like a collection.
    public func series(in collection: ServerCollection, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        let libraries = scopedLibraryIDs
        if libraries?.isEmpty == true { return Paged(items: [], hasMore: false) }
        switch collection.kind {
        case .collection:
            let whole = libraries != nil
            if whole, page > 1 { return Paged(items: [], hasMore: false) }
            let size = whole ? 0 : pageSize
            let items: [KavitaSeriesDTO] = try await withAuth {
                try await $0.get("api/Series/series-by-collection",
                                 query: ["collectionId": collection.collectionID, "pageNumber": String(whole ? 1 : page),
                                         "pageSize": String(size)])
            }
            return Paged(items: items.map(summary).scoped(to: categoryScope), hasMore: !whole && items.count >= pageSize)
        case .smartFilter:
            guard let encoded = collection.payload, !encoded.isEmpty else { return Paged(items: [], hasMore: false) }
            return try await withAuth { client in
                var filter: KavitaDecodedFilter = try await client.post(
                    "api/filter/decode", body: KavitaDecodeFilterDTO(encodedFilter: encoded))
                var whole = false
                if let libraries {
                    if filter.isAnd {
                        let statement = KavitaFilterV2.libraries(libraries)
                        filter.statements = (filter.statements ?? [])
                            + [.init(comparison: statement.comparison, field: statement.field, value: statement.value)]
                        filter.combination = 1
                    } else {
                        whole = true
                    }
                }
                if whole, page > 1 { return Paged(items: [], hasMore: false) }
                let items: [KavitaSeriesDTO] = try await client.post(
                    "api/Series/all-v2",
                    query: ["pageNumber": String(whole ? 1 : page), "pageSize": String(whole ? 0 : pageSize)],
                    body: filter)
                return Paged(items: items.map(self.summary).scoped(to: self.categoryScope),
                             hasMore: !whole && items.count >= pageSize)
            }
        case .readingList:
            return Paged(items: [], hasMore: false)
        }
    }

    public func readingListEntries(_ list: ServerCollection) async throws -> [ReadingListEntry] {
        guard list.kind == .readingList else { return [] }
        let items: [KavitaReadingListItemDTO] = try await withAuth {
            try await $0.get("api/ReadingList/items", query: ["readingListId": list.collectionID])
        }
        return Self.entries(items, client: self)
    }

    static func entries(_ items: [KavitaReadingListItemDTO], client: KavitaClient) -> [ReadingListEntry] {
        let ordered = items.enumerated().sorted { a, b in
            let (oa, ob) = (a.element.order ?? a.offset, b.element.order ?? b.offset)
            return oa != ob ? oa < ob : a.offset < b.offset
        }
        var result: [ReadingListEntry] = []
        for (_, item) in ordered {
            // Chapters from libraries the profile didn't pick are left out.
            if let scope = client.categoryScope, let library = item.libraryId, !scope.contains(String(library)) {
                continue
            }
            let pages: Int = item.chapter?.pages ?? item.pagesTotal ?? 0
            result.append(ReadingListEntry(
                itemID: String(item.id), order: item.order ?? 0, seriesRef: client.ref(item.seriesId),
                seriesTitle: title(item.seriesName), chapterID: String(item.chapterId),
                volumeID: item.volumeId.map(String.init), libraryID: item.libraryId.map(String.init),
                title: entryTitle(item), pageCount: pages, pagesRead: item.pagesRead ?? 0,
                format: ContentFormat(kavitaFormat: item.seriesFormat),
                coverURL: client.chapterCoverURL(item.chapterId)))
        }
        return result
    }

    /// Kavita's own item title ("Volume 2", "Chapter 5"), else one made from
    /// the chapter's numbers and name.
    static func entryTitle(_ item: KavitaReadingListItemDTO) -> String {
        if let t = text(item.title) { return t }
        let name = text(item.chapter?.titleName) ?? text(item.chapterTitleName)
        let range = text(item.chapter?.range) ?? text(item.chapterNumber)
        switch (range, name) {
        case let (r?, n?): return "Chapter \(r): \(n)"
        case let (r?, nil): return "Chapter \(r)"
        case let (nil, n?): return n
        default: return text(item.volumeNumber).map { "Volume \($0)" } ?? "Chapter"
        }
    }

    static func text(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    static func title(_ s: String?) -> String { text(s) ?? "Untitled" }

    func readingListCoverURL(_ id: Int) -> URL? {
        try? HTTPClient(baseURL: config.baseURL, transport: transport)
            .url("api/Image/readinglist-cover", query: ["readingListId": String(id), "apiKey": apiKey])
    }

    func collectionCoverURL(_ id: Int) -> URL? {
        try? HTTPClient(baseURL: config.baseURL, transport: transport)
            .url("api/Image/collection-cover", query: ["collectionTagId": String(id), "apiKey": apiKey])
    }

    func chapterCoverURL(_ id: Int) -> URL? {
        try? HTTPClient(baseURL: config.baseURL, transport: transport)
            .url("api/Image/chapter-cover", query: ["chapterId": String(id), "apiKey": apiKey])
    }
}
