import SwiftUI
import UIKit
import MangaCore

// Long-press a page (docs/IOS.md §3): bookmark it or share its image.

extension View {
    /// Adds the long-press page menu to an image reader.
    func readerPageMenu(session: ReaderSession) -> some View {
        modifier(ReaderPageMenu(session: session))
    }
}

private struct ReaderPageMenu: ViewModifier {
    let session: ReaderSession
    @Environment(\.imagePipeline) private var pipeline
    @State private var showsMenu = false
    @State private var sharing: SharedPage?
    @State private var loadingShare = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.5) {
                guard session.loadState == .loaded, session.edge == nil, !session.isMenuPresented,
                      !session.isTutorial else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showsMenu = true
            }
            .confirmationDialog("Page \(session.currentPage + 1)", isPresented: $showsMenu, titleVisibility: .visible) {
                Button(session.isShowingBookmarkedPage ? "Remove Bookmark" : "Bookmark This Page") {
                    session.toggleBookmark()
                }
                .accessibilityIdentifier("reader.pageMenu.bookmark")
                Button("Share Page") { Task { await share() } }
                    .accessibilityIdentifier("reader.pageMenu.share")
            }
            .sheet(item: $sharing) { page in
                ActivitySheet(items: [page.image])
                    .presentationDetents([.medium, .large])
            }
    }

    /// Loads the page on screen at a good sharing size and opens the share sheet.
    private func share() async {
        guard !loadingShare, let url = session.page(session.currentPage)?.url else { return }
        loadingShare = true
        defer { loadingShare = false }
        let images = PageImages(pipeline: pipeline, server: session.server,
                                targetSize: CGSize(width: 2048, height: 2048))
        guard let loaded = try? await images.load(url) else {
            session.show(ReaderNotice(text: "Couldn't load the page", systemImage: "exclamationmark.triangle"))
            return
        }
        sharing = SharedPage(image: UIImage(cgImage: loaded.cgImage))
    }
}

private struct SharedPage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The system share sheet.
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
