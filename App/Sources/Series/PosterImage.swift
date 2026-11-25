import SwiftUI
import UIKit
import MangaCore

// Stand-in for workstream B's `RemoteImage(url:server:contentMode:)`.
// Once the image pipeline lands, replace the body of `PosterImage` with
// `RemoteImage(url: url, server: server, contentMode: .fill)`; callers
// don't change.

/// A cover image fetched through the server's `imageRequest(_:)`, so
/// Kavita and Suwayomi auth both work. Shows the title on a tinted card
/// while loading or when there's no cover.
struct PosterImage: View {
    let url: URL?
    let server: MangaServer?
    var title: String = ""

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(16)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url, let server else { image = nil; return }
        if let cached = PosterCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        image = nil
        guard let (data, response) = try? await URLSession.shared.data(for: server.imageRequest(url)),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let decoded = UIImage(data: data) else { return }
        PosterCache.shared.setObject(decoded, forKey: url as NSURL)
        if !Task.isCancelled { image = decoded }
    }
}

enum PosterCache {
    static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 400
        return cache
    }()
}
