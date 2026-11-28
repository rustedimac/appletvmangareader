import SwiftUI
import MangaCore

/// What series detail hands to the reader.
struct ReaderRoute: Identifiable {
    let id = UUID()
    let series: SeriesSummary
    let chapters: [Chapter]
    let start: Chapter
    /// Page to open at (a bookmark). Nil resumes saved progress.
    var startPage: Int? = nil
}

/// Presents the reader full screen from series detail.
struct ReaderHost: View {
    let route: ReaderRoute

    var body: some View {
        ReaderView(series: route.series, chapters: route.chapters, start: route.start, startPage: route.startPage)
            // The reader keeps its own page colors and dark menus, also on
            // iPhone and iPad in light mode. This cover is its own
            // presentation, so it doesn't change the screens behind it.
            .preferredColorScheme(.dark)
    }
}
