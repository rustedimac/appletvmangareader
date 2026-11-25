import SwiftUI
import MangaCore

/// A cover image through the shared image pipeline (`RemoteImage`), with
/// the series title shown on a tinted card while it loads or when there is
/// no cover.
struct PosterImage: View {
    let url: URL?
    let server: MangaServer?
    var title: String = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(16)
            if url != nil {
                RemoteImage(url: url, server: server, contentMode: .fill)
            }
        }
    }
}
