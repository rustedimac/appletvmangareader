import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Suwayomi, like Mihon, bookmarks whole chapters (`isBookmarked`). A page
/// bookmark made in the app bookmarks its chapter on the server; the chapter
/// is unbookmarked when its last page bookmark is removed.
extension SuwayomiClient: BookmarkSyncing {
    public var bookmarkGranularity: BookmarkGranularity { .chapter }

    public func bookmarks(seriesID: String) async throws -> [ServerBookmark] {
        struct Response: Decodable {
            struct Chapter: Decodable { var id: Int; var name: String?; var isBookmarked: Bool? }
            struct Manga: Decodable { var chapters: Nodes<Chapter> }
            var manga: Manga
        }
        guard let id = Int(seriesID) else { throw MangaError.notFound }
        let r: Response = try await graphQL(
            "query($id: Int!) { manga(id: $id) { chapters { nodes { id name isBookmarked } } } }",
            variables: ["id": .int(id)]
        )
        return r.manga.chapters.nodes.filter { $0.isBookmarked == true }.map {
            ServerBookmark(seriesID: seriesID, chapterID: String($0.id), page: nil, chapterTitle: $0.name)
        }
    }

    public func allBookmarks() async throws -> [ServerBookmark] {
        struct Response: Decodable {
            struct Chapter: Decodable { var id: Int; var name: String?; var manga: SuwayomiMangaDTO }
            var chapters: Nodes<Chapter>
        }
        let r: Response = try await graphQL(
            "query { chapters(filter: {inLibrary: {equalTo: true}, isBookmarked: {equalTo: true}}) { nodes { id name manga { \(SuwayomiMangaDTO.fields) } } } }"
        )
        return r.chapters.nodes.map {
            ServerBookmark(seriesID: String($0.manga.id), chapterID: String($0.id), page: nil,
                           chapterTitle: $0.name, series: summary($0.manga))
        }
    }

    public func setBookmark(_ bookmarked: Bool, _ bookmark: Bookmark) async throws {
        struct Response: Decodable {
            struct Payload: Decodable { var clientMutationId: String? }
            var updateChapter: Payload
        }
        guard let id = Int(bookmark.chapterID) else { throw MangaError.notFound }
        let _: Response = try await graphQL(
            "mutation($id: Int!, $bookmarked: Boolean!) { updateChapter(input: {id: $id, patch: {isBookmarked: $bookmarked}}) { clientMutationId } }",
            variables: ["id": .int(id), "bookmarked": .bool(bookmarked)]
        )
    }
}
