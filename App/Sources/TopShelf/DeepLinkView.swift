import SwiftUI
import MangaCore

/// What a Top Shelf link opens, presented full screen over the tabs.
struct DeepLinkRoute: Identifiable {
    let id = UUID()
    let link: DeepLink
    /// A profile that asks for its PIN to open: the link waits for the PIN
    /// before switching to it.
    var unlocking: UUID? = nil
}

extension AppModel {
    /// Prepares the app for a link: switches to the profile it was made for
    /// (if it still exists) and closes "Who's reading?". Returns the route
    /// to present, or nil when the link's server is gone. A profile that
    /// asks for its PIN isn't opened yet; the route asks for the PIN first.
    func route(for link: DeepLink) -> DeepLinkRoute? {
        guard state.server(link.ref.serverID) != nil else { return nil }
        // Top Shelf links belong to a real profile.
        if isGuest { endGuestSession(showPicker: false) }
        var target = activeProfile.id
        if let profile = link.profile, state.profiles.contains(where: { $0.id == profile }) {
            target = profile
        }
        if needsPINToOpen(target) {
            return DeepLinkRoute(link: link, unlocking: target)
        }
        openForLink(target)
        return DeepLinkRoute(link: link)
    }

    /// Switches to the link's profile and closes "Who's reading?".
    func openForLink(_ profile: UUID) {
        if profile != activeProfile.id || isPickingProfile {
            pickProfile(profile)
        }
    }
}

/// Asks for the PIN of the profile a link belongs to, then shows the link.
/// Menu goes back to where the app was, without switching profiles.
struct DeepLinkHost: View {
    let route: DeepLinkRoute

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false

    var body: some View {
        if let profile = route.unlocking, !unlocked {
            let name = model.state.profiles.first { $0.id == profile }?.name
            PINPadView(title: name.map { "Enter \($0)'s PIN" } ?? "Enter the PIN",
                       message: "This item belongs to a profile with a PIN.") { pin in
                let result = model.attemptPIN(pin, candidates: [profile])
                if case .unlocked = result {
                    model.openForLink(profile)
                    unlocked = true
                }
                return PINGate<EmptyView>.feedback(result)
            }
            .onExitCommand { dismiss() }
        } else {
            DeepLinkView(link: route.link)
        }
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
                    .accessibilityIdentifier("deepLink.loading")
                    .onExitCommand { dismiss() }
            }
        }
        // No accessibilityIdentifier on this Group: it would land on each
        // child and replace theirs (the reader's "reader.paged").
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
                    // Dark whatever the app theme, like ReaderHost.
                    .preferredColorScheme(.dark)
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
