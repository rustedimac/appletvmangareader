import SwiftUI
import MangaCore

private struct ImagePipelineKey: EnvironmentKey {
    static let defaultValue: any ImageLoading = ImagePipeline.shared
}

extension EnvironmentValues {
    /// The image loader views use. Defaults to `ImagePipeline.shared`;
    /// override it in previews or tests with `.environment(\.imagePipeline, …)`.
    var imagePipeline: any ImageLoading {
        get { self[ImagePipelineKey.self] }
        set { self[ImagePipelineKey.self] = newValue }
    }
}

/// An image from a manga server: a cover or a page. Fills the space it's
/// given, downsampled to that size, with a placeholder while loading and an
/// icon if it fails.
///
/// ```swift
/// RemoteImage(url: series.coverURL, server: client, contentMode: .fill)
///     .frame(width: 240, height: 360)
/// ```
struct RemoteImage: View {
    let url: URL?
    let server: MangaServer?
    var contentMode: ContentMode = .fit
    /// Called once with the original pixel size when the image loads.
    var onPixelSize: ((PageSize) -> Void)? = nil

    @Environment(\.imagePipeline) private var pipeline
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedImage?
    @State private var loadedKey: LoadKey?
    @State private var failed = false

    init(url: URL?, server: MangaServer?, contentMode: ContentMode = .fit, onPixelSize: ((PageSize) -> Void)? = nil) {
        self.url = url
        self.server = server
        self.contentMode = contentMode
        self.onPixelSize = onPixelSize
    }

    private struct LoadKey: Hashable {
        var url: URL?
        var width: Int
        var height: Int
    }

    var body: some View {
        GeometryReader { geo in
            let key = loadKey(for: geo.size)
            content(cached: cached(for: key))
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .task(id: key) { await load(key) }
        }
    }

    @ViewBuilder
    private func content(cached: LoadedImage?) -> some View {
        if let image = loaded ?? cached {
            Image(uiImage: image.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: contentMode)
                .accessibilityIdentifier("remoteImage.loaded")
        } else if failed || url == nil || server == nil {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: url == nil ? "photo" : "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("remoteImage.failed")
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                ProgressView()
            }
            .accessibilityIdentifier("remoteImage.loading")
        }
    }

    private var scaling: ImageScaling { contentMode == .fill ? .fill : .fit }

    private func loadKey(for size: CGSize) -> LoadKey {
        LoadKey(url: url, width: Int((size.width * displayScale).rounded(.up)), height: Int((size.height * displayScale).rounded(.up)))
    }

    private func target(_ key: LoadKey) -> CGSize {
        CGSize(width: key.width, height: key.height)
    }

    private func cached(for key: LoadKey) -> LoadedImage? {
        guard loaded == nil, let url = key.url, key.width > 0 || key.height > 0 else { return nil }
        return pipeline.cachedImage(for: url, targetSize: target(key), scaling: scaling)
    }

    private func load(_ key: LoadKey) async {
        guard let url = key.url, let server else { return }
        // Wait for a real layout before decoding.
        guard key.width > 0 || key.height > 0 else { return }
        if key.url != loadedKey?.url {
            loaded = nil
            failed = false
        }
        do {
            let image = try await pipeline.load(url, server: server, targetSize: target(key), scaling: scaling)
            if Task.isCancelled { return }
            let first = loadedKey?.url != key.url
            loaded = image
            loadedKey = key
            failed = false
            if first { onPixelSize?(image.pixelSize) }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            if loaded == nil { failed = true }
        }
    }
}
