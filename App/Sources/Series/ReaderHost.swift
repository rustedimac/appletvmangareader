import SwiftUI
import MangaCore

/// What series detail hands to the reader.
struct ReaderRoute: Identifiable {
    let id = UUID()
    let series: SeriesSummary
    let chapters: [Chapter]
    let start: Chapter
}

/// Presents the reader full screen from series detail.
struct ReaderHost: View {
    let route: ReaderRoute

    var body: some View {
        ReaderView(series: route.series, chapters: route.chapters, start: route.start)
    }
}
