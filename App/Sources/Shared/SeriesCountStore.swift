import Foundation
import Observation
import MangaCore

/// Chapter counts for posters whose listing left them out (Kavita lists
/// pages, not chapters). A poster asks as it appears; requests run a few
/// at a time, newest first, so a big library loads as fast as before and
/// counts fill in on the posters on screen. Kept in memory for the session.
@MainActor
@Observable
final class SeriesCountStore {
    private(set) var counts: [SeriesRef: SeriesCount] = [:]
    @ObservationIgnored private var inFlight: Set<SeriesRef> = []
    @ObservationIgnored private var failed: Set<SeriesRef> = []
    @ObservationIgnored private var queue: [(SeriesRef, MangaServer)] = []
    @ObservationIgnored private var running = 0
    @ObservationIgnored let maxConcurrent = 4

    func count(for ref: SeriesRef) -> SeriesCount? { counts[ref] }

    /// Saves a count learned elsewhere (series detail), unless the server
    /// already gave one (its unit may be more precise, like volumes).
    func record(_ count: SeriesCount, for ref: SeriesRef) {
        guard counts[ref] == nil else { return }
        counts[ref] = count
    }

    /// Queues a request for `ref` unless it's known, queued or failed.
    func request(_ ref: SeriesRef, client: MangaServer) {
        guard counts[ref] == nil, !failed.contains(ref), inFlight.insert(ref).inserted else { return }
        queue.append((ref, client))
        pump()
    }

    /// A poster scrolled away: drop its request if it hasn't started.
    func cancel(_ ref: SeriesRef) {
        guard let i = queue.firstIndex(where: { $0.0 == ref }) else { return }
        queue.remove(at: i)
        inFlight.remove(ref)
    }

    private func pump() {
        while running < maxConcurrent, let next = queue.popLast() {
            let (ref, client) = next
            running += 1
            Task {
                let result = try? await client.chapterCount(seriesID: ref.seriesID)
                running -= 1
                inFlight.remove(ref)
                if let result { counts[ref] = result } else { failed.insert(ref) }
                pump()
            }
        }
    }
}
