import Foundation

/// Demo reading lists, collections and smart filters, offered by demo
/// servers of the Kavita kind (like the real Kavita client), none by others.
///
/// - Reading list "Demo Reading Order" (id rl-1): chapter 1 of series 1, 2
///   and 3, then chapter 2 of series 1, in that order.
/// - Reading list "Empty List" (rl-2): no items.
/// - Collection "Harbor Picks" (c-1, promoted): every series whose title
///   starts with "Harbor" (ids 2, 10, 18, …).
/// - Smart filter "Every Fifth" (sf-1): series 5, 10, 15, ….
extension SampleLibraryServer {
    public var collectionSupport: ServerCollectionSupport { config.kind == .kavita ? .all : [] }

    public func collections(_ kind: ServerCollectionKind) async throws -> [ServerCollection] {
        guard collectionSupport.contains(kind) else { return [] }
        try await wait()
        let id = config.id
        switch kind {
        case .readingList:
            return [ServerCollection(serverID: id, kind: .readingList, collectionID: "rl-1", title: "Demo Reading Order",
                                     summary: "Starts three demo series, then goes back to the first.",
                                     itemCount: Self.readingOrder.count),
                    ServerCollection(serverID: id, kind: .readingList, collectionID: "rl-2", title: "Empty List", itemCount: 0)]
        case .collection:
            return [ServerCollection(serverID: id, kind: .collection, collectionID: "c-1", title: "Harbor Picks",
                                     summary: "Every Harbor series.", itemCount: collectionMembers("c-1").count,
                                     promoted: true)]
        case .smartFilter:
            return [ServerCollection(serverID: id, kind: .smartFilter, collectionID: "sf-1", title: "Every Fifth",
                                     payload: "demo")]
        }
    }

    /// (series, chapter) pairs of reading list rl-1.
    static let readingOrder = [(1, 1), (2, 1), (3, 1), (1, 2)]

    func collectionMembers(_ id: String) -> [Int] {
        let all = Array(1...seriesCount)
        switch id {
        case "c-1": return all.filter { Self.title(for: $0).hasPrefix("Harbor") }
        case "sf-1": return all.filter { $0 % 5 == 0 }
        default: return []
        }
    }

    public func series(in collection: ServerCollection, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> {
        guard collectionSupport.contains(collection.kind), !collection.kind.holdsChapters else {
            return Paged(items: [], hasMore: false)
        }
        try await wait()
        let ids = collectionMembers(collection.collectionID)
        let start = max(0, (page - 1) * pageSize)
        guard start < ids.count else { return Paged(items: [], hasMore: false) }
        let end = min(ids.count, start + pageSize)
        let items = ids[start..<end].map(summary).filter { s in
            categoryScope.map { scope in s.memberCategoryIDs?.contains(where: scope.contains) ?? true } ?? true
        }
        return Paged(items: items, hasMore: end < ids.count)
    }

    public func readingListEntries(_ list: ServerCollection) async throws -> [ReadingListEntry] {
        guard collectionSupport.contains(.readingLists), list.collectionID == "rl-1" else { return [] }
        try await wait()
        return Self.readingOrder.enumerated().compactMap { index, pair in
            let (n, c) = pair
            guard let chapter = chapters(n).first(where: { $0.id == "\(n)-\(c)" }) else { return nil }
            let read = chapter.isRead ? chapter.pageCount : (chapter.lastPageRead > 0 ? chapter.lastPageRead + 1 : 0)
            return ReadingListEntry(itemID: "rl-1-\(index)", order: index, seriesRef: chapter.seriesRef,
                                    seriesTitle: Self.title(for: n), chapterID: chapter.id, libraryID: "all",
                                    title: chapter.title, pageCount: chapter.pageCount, pagesRead: read)
        }
    }
}
