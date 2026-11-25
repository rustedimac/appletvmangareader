import SwiftUI
import MangaCore

/// What a Top Shelf link opens, presented full screen over the tabs.
struct DeepLinkRoute: Identifiable {
    let id = UUID()
    let link: DeepLink
}

extension AppModel {
    /// Prepares the app for a link: switches to the profile it was made for
    /// (if it still exists) and closes "Who's reading?". Returns the route
    /// to present, or nil when the link's server is gone.
    func route(for link: DeepLink) -> DeepLinkRoute? {
        guard state.server(link.ref.serverID) != nil else { return nil }
        if let profile = link.profile, profile != activeProfile.id,
           state.profiles.contains(where: { $0.id == profile }) {
            pickProfile(profile)
        } else if isPickingProfile {
            pickProfile(activeProfile.id)
        }
        return DeepLinkRoute(link: link)
    }
}

/// Loads the series behind a link, then shows its detail page or opens the
/// reader on the linked chapter. Menu goes back to where the app was.
struct DeepLinkView: View {
    let link: DeepLink

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var detail: SeriesDetail?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else if let errorMessage {
                BrowseMessage(title: "Couldn't open this series", message: errorMessage,
                              systemImage: "exclamationmark.triangle") { Task { await load() } }
                    .onExitCommand { dismiss() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onExitCommand { dismiss() }
            }
        }
        .accessibilityIdentifier("deepLink")
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ detail: SeriesDetail) -> some View {
        switch link {
        case .series:
            NavigationStack {
                SeriesDetailView(series: summary(detail))
                    .seriesNavigation()
            }
        case .read(_, let chapterID, let page, _):
            if let chapter = detail.chapters.first(where: { $0.id == chapterID }) ?? detail.continueChapter {
                ReaderView(series: summary(detail), chapters: detail.chapters, start: chapter,
                           startPage: chapter.id == chapterID ? page : nil)
            } else {
                NavigationStack { SeriesDetailView(series: summary(detail)) }
            }
        }
    }

    /// The server's summary, with the library id and cover the profile
    /// already knows (Kavita needs the library id to save progress).
    private func summary(_ detail: SeriesDetail) -> SeriesSummary {
        var s = detail.summary
        if let known = model.state.knownSummary(link.ref, profile: model.activeProfile.id) {
            s.libraryID = s.libraryID ?? known.libraryID
            s.coverURL = s.coverURL ?? known.coverURL
            if s.title.isEmpty { s.title = known.title }
        }
        return s
    }

    private func load() async {
        errorMessage = nil
        do {
            detail = try await model.seriesDetail(link.ref)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
