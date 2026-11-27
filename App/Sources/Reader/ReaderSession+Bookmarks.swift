import Foundation
import MangaCore

/// A message shown briefly over the page.
struct ReaderNotice: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
}

/// A request for the webtoon strip to scroll to a page of a chapter it holds.
struct PageJump: Equatable {
    let id = UUID()
    let chapterID: String
    let page: Int
}

/// Page bookmarks from inside the reader. The menu's Bookmark button and,
/// in the paged reader, a press up on the remote toggle the page on screen.
extension ReaderSession {
    /// Bookmarks in this series, in reading order.
    var seriesBookmarks: [Bookmark] { model.bookmarks(for: series.ref) }

    /// Bookmarks among the pages on screen (a two-page spread has two).
    var visibleBookmarks: [Bookmark] {
        guard loadState == .loaded, edge == nil else { return [] }
        let pages = Set(visiblePages)
        return seriesBookmarks.filter { $0.chapterID == chapter.id && pages.contains($0.page) }
    }

    var isShowingBookmarkedPage: Bool {
        if isTutorial {
            return loadState == .loaded && edge == nil && !tutorialBookmarks.isDisjoint(with: visiblePages)
        }
        return !visibleBookmarks.isEmpty
    }

    /// Bookmarks the page on screen, or removes the bookmark if any page on
    /// screen has one.
    func toggleBookmark() {
        guard loadState == .loaded, pageCount > 0, edge == nil else { return }
        if isTutorial { return toggleTutorialBookmark() }
        let existing = visibleBookmarks
        if existing.isEmpty {
            let page = min(currentPage, pageCount - 1)
            model.addBookmark(series: series, chapter: chapter, page: page)
            show(ReaderNotice(text: "Bookmarked page \(page + 1)", systemImage: "bookmark.fill"))
        } else {
            for bookmark in existing { model.removeBookmark(bookmark) }
            show(ReaderNotice(text: "Bookmark removed", systemImage: "bookmark.slash"))
        }
    }

    /// Opens a bookmark: turns to its page, loading its chapter if needed.
    func open(_ bookmark: Bookmark) {
        isMenuPresented = false
        if bookmark.chapterID == chapter.id, loadState == .loaded {
            let page = min(bookmark.page, max(0, pageCount - 1))
            go(toPage: page)
            pageJump = PageJump(chapterID: chapter.id, page: page)
        } else if let target = chapters.first(where: { $0.id == bookmark.chapterID }) {
            Task { await load(chapter: target, startPage: bookmark.page) }
        }
    }

    func show(_ notice: ReaderNotice) {
        self.notice = notice
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }
}
