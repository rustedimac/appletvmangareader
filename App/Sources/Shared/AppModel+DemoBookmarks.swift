import Foundation
import MangaCore

extension AppModel {
    /// With `-demoServers -demoFavorites`, favorites four "Demo Kavita"
    /// series with known sort values and adds two bookmarks, for the
    /// Favorites sort and Bookmarks UI tests.
    ///
    /// | Series                 | Favorited | Updated | Last read | Unread |
    /// | ---------------------- | --------- | ------- | --------- | ------ |
    /// | 1 Ember Chronicles 1   | 3rd       | oldest  | 2nd       | 4      |
    /// | 2 Harbor Chronicles 2  | newest    | 2nd     | never     | 1      |
    /// | 3 Lantern Chronicles 3 | oldest    | 3rd     | newest    | 9      |
    /// | 4 Meadow Chronicles 4  | 2nd       | newest  | never     | 6      |
    ///
    /// Bookmarks: series 1, Chapter 2, page 5; series 2, Chapter 1, page 1.
    func installDemoFavoritesAndBookmarks() {
        guard let server = servers.first(where: { $0.name == "Demo Kavita" }) else { return }
        let profile = activeProfile.id
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        func summary(_ n: Int) -> SeriesSummary {
            SeriesSummary(ref: SeriesRef(serverID: server.id, seriesID: String(n)),
                          title: SampleLibraryServer.title(for: n), coverURL: nil, libraryID: "all")
        }
        let favorited: [Int: Double] = [1: 2, 2: 4, 3: 1, 4: 3]
        let updated: [Int: Double] = [1: 1, 2: 3, 3: 2, 4: 4]
        let unread: [Int: Int] = [1: 4, 2: 1, 3: 9, 4: 6]
        update { s in
            for n in 1...4 {
                s.setFavorite(summary(n), true, profile: profile, now: base.addingTimeInterval(favorited[n]! * 3600))
                let detail = SeriesDetail(summary: summary(n), synopsis: nil, authors: [], genres: [], status: nil,
                                          chapters: (0..<unread[n]!).map {
                                              Chapter(id: "\(n)-\($0 + 1)", seriesRef: summary(n).ref,
                                                      title: "Chapter \($0 + 1)", number: Double($0 + 1), pageCount: 20,
                                                      updatedAt: base.addingTimeInterval(updated[n]! * 86_400))
                                          })
                s.updateFavorite(from: detail, profile: profile, now: Date())
            }
            s.recordProgress(summary(1).ref, chapterID: "1-1", page: 3, completed: false, profile: profile,
                             now: base.addingTimeInterval(10 * 86_400))
            s.recordProgress(summary(3).ref, chapterID: "3-1", page: 3, completed: false, profile: profile,
                             now: base.addingTimeInterval(20 * 86_400))
            s.setBookmark(Bookmark(series: summary(1), chapterID: "1-2", chapterTitle: "Chapter 2", chapterNumber: 2,
                                   page: 4, createdAt: base), true, profile: profile)
            s.setBookmark(Bookmark(series: summary(2), chapterID: "2-1", chapterTitle: "Chapter 1", chapterNumber: 1,
                                   page: 0, createdAt: base.addingTimeInterval(60)), true, profile: profile)
        }
    }
}
