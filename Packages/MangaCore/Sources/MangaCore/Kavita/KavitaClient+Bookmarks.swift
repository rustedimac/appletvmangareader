import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Kavita bookmarks pages for each Kavita user (`api/Reader/bookmark`).
/// The user needs Kavita's Bookmark role; without it the calls fail and the
/// app keeps the bookmark locally.
extension KavitaClient: BookmarkSyncing {
    public var bookmarkGranularity: BookmarkGranularity { .page }

    public func bookmarks(seriesID: String) async throws -> [ServerBookmark] {
        guard Int(seriesID) != nil else { throw MangaError.notFound }
        let items: [KavitaBookmarkDTO] = try await withAuth {
            try await $0.get("api/Reader/series-bookmarks", query: ["seriesId": seriesID])
        }
        return items.map(serverBookmark)
    }

    public func allBookmarks() async throws -> [ServerBookmark] {
        let items: [KavitaBookmarkDTO] = try await withAuth {
            try await $0.post("api/Reader/all-bookmarks", body: KavitaFilterV2())
        }
        return items.map(serverBookmark)
    }

    public func setBookmark(_ bookmarked: Bool, _ bookmark: Bookmark) async throws {
        guard let chapterID = Int(bookmark.chapterID),
              let seriesID = Int(bookmark.series.ref.seriesID),
              let volumeID = bookmark.volumeID.flatMap(Int.init) else {
            throw MangaError.notFound
        }
        let body = KavitaBookmarkRequest(page: bookmark.page, volumeId: volumeID, seriesId: seriesID, chapterId: chapterID)
        try await withAuth {
            try await $0.postIgnoringResponse(bookmarked ? "api/Reader/bookmark" : "api/Reader/unbookmark", body: body)
        }
    }

    func serverBookmark(_ dto: KavitaBookmarkDTO) -> ServerBookmark {
        ServerBookmark(seriesID: String(dto.seriesId), chapterID: String(dto.chapterId),
                       volumeID: dto.volumeId.map(String.init), page: dto.page,
                       chapterTitle: dto.chapterTitle?.isEmpty == false ? dto.chapterTitle : nil,
                       series: dto.series.map(summary))
    }
}

/// Kavita's BookmarkDto. `series` is only filled in by `all-bookmarks`.
struct KavitaBookmarkDTO: Decodable {
    var id: Int?
    var page: Int
    var volumeId: Int?
    var seriesId: Int
    var chapterId: Int
    var chapterTitle: String?
    var series: KavitaSeriesDTO?
}

struct KavitaBookmarkRequest: Encodable {
    var page: Int
    var volumeId: Int
    var seriesId: Int
    var chapterId: Int
}
