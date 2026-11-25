import Foundation
import MangaCore

/// Bookmarks and Favorites sorting for the active profile.
///
/// Bookmarks are always saved locally. When the profile syncs to the
/// series' server (`syncsProgress(to:)`) and the client supports it
/// (`BookmarkSyncing`), they are also written to the server and merged
/// back from it: Kavita keeps page bookmarks per Kavita user, Suwayomi
/// bookmarks whole chapters.
extension AppModel {
    // MARK: Bookmarks

    /// Every bookmark of the active profile, newest first.
    var bookmarks: [Bookmark] { state.bookmarks(profile: activeProfile.id) }

    func bookmarks(for ref: SeriesRef) -> [Bookmark] {
        state.bookmarks(for: ref, profile: activeProfile.id)
    }

    func isBookmarked(_ ref: SeriesRef, chapterID: String, page: Int) -> Bool {
        state.isBookmarked(ref, chapterID: chapterID, page: page, profile: activeProfile.id)
    }

    func addBookmark(series: SeriesSummary, chapter: Chapter, page: Int) {
        let bookmark = Bookmark(series: series, chapter: chapter, page: page)
        let profile = activeProfile.id
        guard !isBookmarked(series.ref, chapterID: chapter.id, page: page) else { return }
        let existing = bookmarks(for: series.ref)
        update { $0.setBookmark(bookmark, true, profile: profile) }
        guard let client = bookmarkClient(for: series.ref) else { return }
        guard BookmarkSync.shouldSendAddition(of: bookmark, existing: existing, granularity: client.bookmarkGranularity) else {
            update { $0.markBookmarksUploaded([bookmark.id], profile: profile) }
            return
        }
        Task {
            do {
                try await client.setBookmark(true, bookmark)
                update { $0.markBookmarksUploaded([bookmark.id], profile: profile) }
            } catch {
                // Stays marked for upload; the next sync retries it.
            }
        }
    }

    func removeBookmark(_ bookmark: Bookmark) {
        let profile = activeProfile.id
        update { $0.setBookmark(bookmark, false, profile: profile) }
        guard !bookmark.needsUpload, let client = bookmarkClient(for: bookmark.series.ref) else { return }
        let remaining = bookmarks(for: bookmark.series.ref)
        guard BookmarkSync.shouldSendRemoval(of: bookmark, remaining: remaining,
                                             granularity: client.bookmarkGranularity) else { return }
        Task { try? await client.setBookmark(false, bookmark) }
    }

    /// The client to sync a series' bookmarks with, or nil to keep them local.
    func bookmarkClient(for ref: SeriesRef) -> BookmarkSyncing? {
        guard syncsProgress(to: ref.serverID) else { return nil }
        return client(for: ref) as? BookmarkSyncing
    }

    /// Merges one series' bookmarks with the server and uploads any that
    /// are waiting.
    func syncBookmarks(for detail: SeriesDetail) async {
        let ref = detail.summary.ref
        let profile = activeProfile.id
        guard let client = bookmarkClient(for: ref),
              let remote = try? await client.bookmarks(seriesID: ref.seriesID) else { return }
        let merged = BookmarkSync.merge(local: bookmarks(for: ref), server: remote,
                                        granularity: client.bookmarkGranularity,
                                        series: { $0 == ref.seriesID ? detail.summary : nil })
        update {
            $0.replaceBookmarks(where: { $0.series.ref == ref }, with: merged, profile: profile)
            $0.updateBookmarkChapters(from: detail, profile: profile)
        }
        await uploadPending(merged, client: client)
    }

    /// Merges every server's bookmarks (for the Bookmarks tab).
    func syncAllBookmarks() async {
        let profile = activeProfile.id
        for server in servers {
            let probe = SeriesRef(serverID: server.id, seriesID: "")
            guard let client = bookmarkClient(for: probe),
                  let remote = try? await client.allBookmarks() else { continue }
            let local = bookmarks.filter { $0.series.ref.serverID == server.id }
            let favorites = Dictionary(favoriteSeries(on: server.id).map { ($0.series.ref.seriesID, $0.series) },
                                       uniquingKeysWith: { a, _ in a })
            let merged = BookmarkSync.merge(local: local, server: remote, granularity: client.bookmarkGranularity,
                                            series: { favorites[$0] })
            update { $0.replaceBookmarks(where: { $0.series.ref.serverID == server.id }, with: merged, profile: profile) }
            await uploadPending(merged, client: client)
        }
    }

    private func uploadPending(_ bookmarks: [Bookmark], client: BookmarkSyncing) async {
        let profile = activeProfile.id
        var done = Set<String>()
        var chaptersSent = Set<String>()
        for b in bookmarks where b.needsUpload {
            // Chapter servers need one call per chapter.
            if client.bookmarkGranularity == .chapter {
                let key = "\(b.series.ref.seriesID)|\(b.chapterID)"
                if chaptersSent.contains(key) || bookmarks.contains(where: {
                    !$0.needsUpload && $0.series.ref == b.series.ref && $0.chapterID == b.chapterID
                }) {
                    done.insert(b.id)
                    continue
                }
                chaptersSent.insert(key)
            }
            if (try? await client.setBookmark(true, b)) != nil { done.insert(b.id) }
        }
        guard !done.isEmpty else { return }
        update { $0.markBookmarksUploaded(done, profile: profile) }
    }

    private func favoriteSeries(on serverID: UUID) -> [Favorite] {
        state.favorites(profile: activeProfile.id).filter { $0.series.ref.serverID == serverID }
    }

    // MARK: Series detail

    /// Call when series detail loads: refreshes the favorite's sort data,
    /// fills in bookmark chapter names and syncs bookmarks.
    func didLoadSeriesDetail(_ detail: SeriesDetail) async {
        let profile = activeProfile.id
        update {
            $0.updateFavorite(from: detail, profile: profile)
            $0.updateBookmarkChapters(from: detail, profile: profile)
        }
        await syncBookmarks(for: detail)
    }

    // MARK: Favorites sort

    var favoritesSort: FavoritesSort { state.favoritesSort(profile: activeProfile.id) }

    func setFavoritesSort(_ sort: FavoritesSort) {
        let profile = activeProfile.id
        update { $0.setFavoritesSort(sort, profile: profile) }
    }

    /// The Favorites tab's series in the profile's chosen order.
    var sortedFavorites: [Favorite] {
        state.sorted(favorites, profile: activeProfile.id)
    }

    /// Reloads series detail for favorites whose "Updated" and "Unread"
    /// values are missing or more than an hour old, four at a time.
    func refreshStaleFavorites(maxAge: TimeInterval = 3600) async {
        let profile = activeProfile.id
        let stale = state.favoritesNeedingRefresh(profile: profile, maxAge: maxAge)
        guard !stale.isEmpty else { return }
        let refs = stale.map(\.series.ref)
        let details = await withTaskGroup(of: SeriesDetail?.self, returning: [SeriesDetail].self) { group in
            var nextIndex = 0
            while nextIndex < min(4, refs.count) {
                let ref = refs[nextIndex]
                group.addTask { [weak self] in try? await self?.seriesDetail(ref) }
                nextIndex += 1
            }
            var loaded: [SeriesDetail] = []
            while let detail = await group.next() {
                if let detail { loaded.append(detail) }
                if nextIndex < refs.count {
                    let ref = refs[nextIndex]
                    group.addTask { [weak self] in try? await self?.seriesDetail(ref) }
                    nextIndex += 1
                }
            }
            return loaded
        }
        // Series that failed to load still count as refreshed for a while,
        // so an offline server isn't asked again on every visit.
        update { s in
            for detail in details { s.updateFavorite(from: detail, profile: profile) }
            for f in s.favoritesNeedingRefresh(profile: profile, maxAge: maxAge) {
                s.markFavoriteRefreshed(f.series.ref, profile: profile)
            }
        }
    }
}
