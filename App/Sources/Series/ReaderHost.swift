import SwiftUI
import MangaCore

/// What series detail hands to the reader.
struct ReaderRoute: Identifiable {
    let id = UUID()
    let series: SeriesSummary
    let chapters: [Chapter]
    let start: Chapter
}

/// Presents the reader full screen. Until workstream E's
/// `ReaderView(series:chapters:start:)` lands this shows a stand-in; swap
/// the body for `ReaderView(series: route.series, chapters: route.chapters,
/// start: route.start)`.
struct ReaderHost: View {
    let route: ReaderRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 30) {
            Text(route.series.title).font(.title2)
            Text(route.start.title).foregroundStyle(.secondary)
            Text("The reader isn't built yet.").foregroundStyle(.secondary)
            Button("Close") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.placeholder")
    }
}
