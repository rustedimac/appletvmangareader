import Foundation
import TVServices
import UIKit
import MangaCore

/// Keeps the Top Shelf in step with the active profile. After any saved
/// change it rebuilds `TopShelfSnapshot` (Continue Reading and Favorites),
/// writes it and the covers to the App Group, and asks tvOS to reload the
/// Top Shelf extension. The extension only reads those files.
@MainActor
final class TopShelfPublisher {
    let store: TopShelfStore
    private weak var model: AppModel?
    private var pending: Task<Void, Never>?
    private var published: TopShelfSnapshot?
    /// Covers are drawn at the Top Shelf's poster size on a 4K screen.
    static let coverPixelSize = CGSize(width: 800, height: 1200)
    /// Progress saves come every couple of seconds while reading.
    var delay: Duration = .seconds(3)

    init(store: TopShelfStore, model: AppModel) {
        self.store = store
        self.model = model
    }

    func schedule() {
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.publish()
        }
    }

    func publish() async {
        guard let model else { return }
        let snapshot = TopShelfSnapshot.make(from: model.state)
        guard snapshot != published else { return }
        published = snapshot
        let changed = (try? store.save(snapshot)) ?? false
        if changed { TVTopShelfContentProvider.topShelfContentDidChange() }

        var added = false
        for cover in snapshot.covers where !store.hasCover(cover.file) {
            guard !Task.isCancelled else { return }
            guard let server = model.state.server(cover.serverID) else { continue }
            let client = model.client(for: server)
            guard let image = try? await ImagePipeline.shared.image(for: cover.url, server: client,
                                                                    targetSize: Self.coverPixelSize),
                  let data = image.jpegData(compressionQuality: 0.8) else { continue }
            try? store.saveCover(data, file: cover.file)
            added = true
        }
        store.pruneCovers(keeping: Set(snapshot.covers.map(\.file)))
        if added { TVTopShelfContentProvider.topShelfContentDidChange() }
    }
}

extension AppModel {
    /// Starts publishing the Top Shelf. Does nothing without the App Group
    /// (unsigned simulator builds) or in UI tests.
    func startTopShelf() {
        guard !Self.topShelfStarted, !UITestingSeed.isUITesting, let store = TopShelfStore.shared else { return }
        Self.topShelfStarted = true
        let publisher = TopShelfPublisher(store: store, model: self)
        stateObservers.append { old, new in
            if old != new { publisher.schedule() }
        }
        publisher.schedule()
    }

    /// Remembers the series being read, for Continue Reading.
    func noteReading(_ series: SeriesSummary) {
        let profile = activeProfile.id
        update { $0.noteRecentSeries(series, profile: profile) }
    }

    private static var topShelfStarted = false
}
