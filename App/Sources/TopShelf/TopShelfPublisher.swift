import Foundation
#if os(tvOS)
import TVServices
#endif
import UIKit
import MangaCore

// The Top Shelf is tvOS only (docs/IOS.md §1); `noteReading` is shared.
#if os(tvOS)
/// Keeps the Top Shelf in step with the active profile. After any saved
/// change it rebuilds `TopShelfSnapshot` (Continue Reading and Favorites),
/// leaving out what the profile's content filter hides, writes it and
/// the covers to the App Group, and asks tvOS to reload the
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
        // The Top Shelf shows the owner's reading, never a guest's.
        guard let model, !model.isGuest else { return }
        // The Top Shelf follows the profile's content filter, and shows
        // nothing for a profile that asks for its PIN to open.
        let profile = model.activeProfile.id
        if model.contentFilter.isActive { await model.refreshHiddenSeries() }
        guard !Task.isCancelled else { return }
        let snapshot = TopShelfSnapshot.make(from: model.state, hidden: model.hiddenSeries,
                                             isPrivate: model.requiresPINToOpen(profile) && model.hasPIN(profile))
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

    private static var topShelfStarted = false
}
#endif

extension AppModel {
    /// Remembers the series being read, for Continue Reading.
    func noteReading(_ series: SeriesSummary) {
        let profile = activeProfile.id
        update { $0.noteRecentSeries(series, profile: profile) }
    }
}
