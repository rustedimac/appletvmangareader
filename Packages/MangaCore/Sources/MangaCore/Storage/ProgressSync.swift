import Foundation

/// A progress change not yet confirmed by the server (the push failed, or
/// the Apple TV was offline). Kept on the series until it is pushed or the
/// server turns out to have newer progress for that chapter.
public struct PendingProgress: Codable, Hashable, Sendable {
    public var chapterID: String
    /// Zero-based page.
    public var page: Int
    public var completed: Bool
    /// When it was read on this Apple TV.
    public var at: Date

    public init(chapterID: String, page: Int, completed: Bool, at: Date) {
        self.chapterID = chapterID
        self.page = page
        self.completed = completed
        self.at = at
    }

    private enum CodingKeys: String, CodingKey { case chapterID, page, completed, at }

    /// An undated change loses to the server's, but isn't thrown away.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterID = try c.decode(String.self, forKey: .chapterID)
        page = try c.decode(Int.self, forKey: .page)
        completed = c.tolerant(.completed, default: false)
        at = c.tolerant(.at, default: .distantPast)
    }
}

/// Merges queued local progress with what a server reports. Latest wins,
/// per chapter: a queued change is kept (and should be pushed) only when
/// it is newer than the server's `lastReadAt` for that chapter, or the
/// server doesn't say when it was read.
public enum ProgressSync {
    public struct Resolution: Equatable, Sendable {
        /// The server's detail with the winning local changes applied.
        public var detail: SeriesDetail
        /// Local changes newer than the server's: push these.
        public var push: [PendingProgress]
        /// Local changes the server has already moved past (or chapters
        /// that no longer exist): forget these.
        public var dropped: [PendingProgress]
    }

    public static func reconcile(_ detail: SeriesDetail, pending: [PendingProgress]) -> Resolution {
        var d = detail
        var push: [PendingProgress] = []
        var dropped: [PendingProgress] = []
        // Oldest first, so a later change to the same chapter wins.
        for p in pending.sorted(by: { $0.at < $1.at }) {
            guard let i = d.chapters.firstIndex(where: { $0.id == p.chapterID }) else {
                dropped.append(p)
                continue
            }
            if let serverAt = d.chapters[i].lastReadAt, serverAt >= p.at {
                dropped.append(p)
                continue
            }
            // Same effect the push has on the server: the page is the
            // position, and a chapter is read only when it was finished.
            d.chapters[i].lastPageRead = p.page
            d.chapters[i].isRead = p.completed
            d.chapters[i].lastReadAt = p.at
            push.removeAll { $0.chapterID == p.chapterID }
            push.append(p)
        }
        return Resolution(detail: d, push: push, dropped: dropped)
    }
}

public extension AppState {
    /// At most this many queued changes are kept per series.
    static let maxPendingPerSeries = 30

    /// Queues a change for the server. One entry per chapter, the newest.
    mutating func queuePending(_ change: PendingProgress, for ref: SeriesRef, profile: UUID) {
        mutateData(profile) { data in
            var p = data.progress[ref.storageKey]
                ?? SeriesProgress(chapterID: change.chapterID, page: change.page, updatedAt: change.at)
            p.pending.removeAll { $0.chapterID == change.chapterID }
            p.pending.append(change)
            if p.pending.count > Self.maxPendingPerSeries {
                p.pending.removeFirst(p.pending.count - Self.maxPendingPerSeries)
            }
            data.progress[ref.storageKey] = p
        }
    }

    /// Forgets queued changes the server now has (or has moved past):
    /// those for these chapters made no later than `through`.
    mutating func clearPending(_ ref: SeriesRef, chapterIDs: Set<String>, through: Date, profile: UUID) {
        mutateData(profile) { data in
            guard var p = data.progress[ref.storageKey], !p.pending.isEmpty else { return }
            p.pending.removeAll { chapterIDs.contains($0.chapterID) && $0.at <= through }
            data.progress[ref.storageKey] = p
        }
    }

    func pending(_ ref: SeriesRef, profile: UUID) -> [PendingProgress] {
        progress(ref, profile: profile)?.pending ?? []
    }

    /// Series on a server with changes waiting to be pushed.
    func seriesWithPending(server: UUID, profile: UUID) -> [SeriesRef] {
        let prefix = server.uuidString + "|"
        return (profileData[profile.uuidString]?.progress ?? [:])
            .filter { $0.key.hasPrefix(prefix) && !$0.value.pending.isEmpty }
            .sorted { $0.key < $1.key }
            .map { SeriesRef(serverID: server, seriesID: String($0.key.dropFirst(prefix.count))) }
    }

    /// A Continue Reading row from this profile's own progress, newest
    /// first, for servers it doesn't sync to.
    func localContinueReading(server: UUID, profile: UUID, limit: Int = 20) -> [SeriesSummary] {
        let prefix = server.uuidString + "|"
        return (profileData[profile.uuidString]?.progress ?? [:])
            .filter { $0.key.hasPrefix(prefix) && !$0.value.chapterID.isEmpty }
            .compactMap { _, p in p.series.map { (p.updatedAt, $0) } }
            .sorted { $0.0 > $1.0 }
            .prefix(limit)
            .map(\.1)
    }
}

public extension SeriesSummary {
    /// A copy safe to keep in `AppState`: Kavita cover URLs carry the
    /// user's API key, which must not leave the Keychain.
    var withoutSecrets: SeriesSummary {
        var s = self
        if let url = coverURL, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems, items.contains(where: { $0.name.lowercased() == "apikey" }) {
            components.queryItems = items.filter { $0.name.lowercased() != "apikey" }
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
            s.coverURL = components.url
        }
        return s
    }
}

/// How long to wait before retrying queued progress pushes after
/// consecutive failures: 5 s, 10 s, 20 s, ... up to 5 minutes, with up to
/// 20% random jitter so several Apple TVs don't retry in lockstep.
public struct RetryBackoff: Sendable, Equatable {
    public var base: Double
    public var maximum: Double
    public var jitter: Double

    public init(base: Double = 5, maximum: Double = 300, jitter: Double = 0.2) {
        self.base = base
        self.maximum = maximum
        self.jitter = jitter
    }

    /// Seconds to wait after `failures` failed attempts in a row (1 or more).
    /// `random` is a value in 0...1 (pass a fixed one in tests).
    public func delay(afterFailures failures: Int, random: Double = Double.random(in: 0...1)) -> Double {
        let n = max(1, failures)
        let exponential = base * pow(2, Double(min(n - 1, 30)))
        let capped = min(maximum, exponential)
        let factor = 1 - jitter * min(1, max(0, random))
        return capped * factor
    }
}

public extension AppState {
    /// Whether any series on these servers has changes waiting to be pushed.
    func hasPending(servers: [UUID], profile: UUID) -> Bool {
        servers.contains { !seriesWithPending(server: $0, profile: profile).isEmpty }
    }
}
