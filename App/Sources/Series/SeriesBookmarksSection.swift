import SwiftUI
import MangaCore

/// Series detail's bookmarked pages, above the chapter list. Picking one
/// opens the reader on that page; holding select offers Remove.
struct SeriesBookmarksSection: View {
    @Environment(AppModel.self) private var model
    let series: SeriesRef
    let chapters: [Chapter]
    let open: (Chapter, Int) -> Void

    var body: some View {
        let bookmarks = model.bookmarks(for: series)
        if !bookmarks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bookmarks")
                    .themedSectionLabel(.headline, fallback: .headline)
                    .accessibilityIdentifier("series.bookmarks")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 30) {
                        ForEach(bookmarks) { bookmark in
                            card(bookmark)
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
            .tvFocusSection()
        }
    }

    private func card(_ bookmark: Bookmark) -> some View {
        let chapter = chapters.first { $0.id == bookmark.chapterID }
        return Button {
            if let chapter { open(chapter, bookmark.page) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(chapter?.title ?? (bookmark.chapterTitle.isEmpty ? "Chapter" : bookmark.chapterTitle),
                      systemImage: "bookmark.fill")
                    .lineLimit(1)
                Text(bookmark.pageLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 380, alignment: .leading)
        }
        .disabled(chapter == nil)
        .accessibilityIdentifier("series.bookmark.\(bookmark.chapterID).\(bookmark.page)")
        .contextMenu {
            Button(role: .destructive) { model.removeBookmark(bookmark) } label: {
                Label("Remove Bookmark", systemImage: "bookmark.slash")
            }
        }
    }
}
