import Foundation

/// How a chapter row shows its progress.
public enum ChapterReadState: Equatable, Sendable {
    case unread
    /// `page` is one-based for display. `pageCount` is nil when the server
    /// doesn't know it yet (Suwayomi reports -1 before pages are fetched).
    case inProgress(page: Int, pageCount: Int?)
    case read

    public var label: String {
        switch self {
        case .unread: return ""
        case .read: return "Read"
        case .inProgress(let page, let count?): return "Page \(page) of \(count)"
        case .inProgress(let page, nil): return "Page \(page)"
        }
    }
}

public extension Chapter {
    var readState: ChapterReadState {
        if isRead { return .read }
        if lastPageRead > 0 { return .inProgress(page: lastPageRead + 1, pageCount: pageCount > 0 ? pageCount : nil) }
        return .unread
    }
}

/// The main button on series detail.
public struct ContinueAction: Equatable, Sendable {
    public var chapter: Chapter
    public var label: String
}

public extension SeriesDetail {
    /// "Start Reading" with no progress, "Continue <chapter>" partway, and
    /// "Read Again" once every chapter is read. Nil with no chapters.
    var continueAction: ContinueAction? {
        guard let chapter = continueChapter else { return nil }
        if chapters.allSatisfy(\.isRead) {
            return ContinueAction(chapter: chapter, label: "Read Again")
        }
        let started = chapters.contains { $0.isRead || $0.lastPageRead > 0 }
        return ContinueAction(chapter: chapter, label: started ? "Continue \(chapter.title)" : "Start Reading")
    }

    var readCount: Int { chapters.filter(\.isRead).count }

    /// Chapters in display order. `chapters` is always reading order.
    func displayChapters(newestFirst: Bool) -> [Chapter] {
        newestFirst ? chapters.reversed() : chapters
    }
}
