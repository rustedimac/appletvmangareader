import Foundation

/// Shares one download between everyone asking for the same key. The
/// download is cancelled only when every waiter has gone.
actor FetchCoalescer {
    private struct Entry {
        let id: UUID
        let task: Task<Data, Error>
        /// Waiters that haven't been cancelled.
        var live: Set<UUID>
    }

    private var entries: [String: Entry] = [:]

    func data(for key: String, fetch: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let waiter = UUID()
        let entry: Entry
        if var existing = entries[key] {
            existing.live.insert(waiter)
            entries[key] = existing
            entry = existing
        } else {
            entry = Entry(id: UUID(), task: Task { try await fetch() }, live: [waiter])
            entries[key] = entry
        }
        let entryID = entry.id
        defer { finish(key, entryID: entryID) }
        return try await withTaskCancellationHandler {
            try await entry.task.value
        } onCancel: {
            Task { await self.cancel(key, entryID: entryID, waiter: waiter) }
        }
    }

    /// Number of downloads in flight. For tests.
    var inFlight: Int { entries.count }

    /// The shared task has produced a result; later callers start fresh
    /// (and will usually hit the disk cache).
    private func finish(_ key: String, entryID: UUID) {
        if entries[key]?.id == entryID { entries[key] = nil }
    }

    private func cancel(_ key: String, entryID: UUID, waiter: UUID) {
        guard var entry = entries[key], entry.id == entryID else { return }
        entry.live.remove(waiter)
        if entry.live.isEmpty {
            entry.task.cancel()
            entries[key] = nil
        } else {
            entries[key] = entry
        }
    }
}

/// Caps parallel downloads. Visible images (`load`) jump ahead of
/// prefetches, and a queued prefetch is promoted if something on screen
/// asks for the same URL.
actor DownloadLimiter {
    private struct Waiter {
        let key: String
        var high: Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    let limit: Int
    private var running = 0
    private var waiters: [Waiter] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func acquire(key: String, high: Bool) async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(key: key, high: high, continuation: continuation))
        }
    }

    func release() {
        let next = waiters.firstIndex(where: \.high) ?? waiters.indices.first
        if let next {
            // The slot passes straight to the next waiter.
            waiters.remove(at: next).continuation.resume()
        } else {
            running -= 1
        }
    }

    func promote(_ key: String) {
        for i in waiters.indices where waiters[i].key == key { waiters[i].high = true }
    }

    var queued: Int { waiters.count }
    var active: Int { running }
}
