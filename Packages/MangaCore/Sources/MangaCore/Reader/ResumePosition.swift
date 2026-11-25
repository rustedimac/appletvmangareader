import Foundation

/// Where the reader opens a chapter when no page was asked for.
///
/// Sources, most trusted first:
/// 1. Where this reading session last was in the chapter (it may have been
///    visited earlier, e.g. read forward, then back into it).
/// 2. This profile's saved progress, written on every page change, when it
///    points at this chapter and is at least as new as the server's
///    (`serverReadAt`; nil when the server doesn't say when it was read).
/// 3. The chapter as the server reported it.
///
/// A chapter left finished on its last page opens at the start, so "Read
/// Again" reads it again; one left partway opens on that exact page.
public enum ResumePosition {
    public static func startPage(for chapter: Chapter,
                                 sessionPage: Int? = nil,
                                 local: SeriesProgress?,
                                 serverReadAt: Date? = nil) -> Int {
        if let sessionPage { return max(0, sessionPage) }
        if let local, local.chapterID == chapter.id, serverReadAt.map({ local.updatedAt >= $0 }) ?? true {
            let finished = local.readChapterIDs.contains(chapter.id) || chapter.isRead
            if finished, chapter.pageCount > 0, local.page >= chapter.pageCount - 1 { return 0 }
            return max(0, local.page)
        }
        if chapter.isRead { return 0 }
        return max(0, chapter.lastPageRead)
    }
}
