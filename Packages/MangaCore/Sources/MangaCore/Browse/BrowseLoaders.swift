import Foundation

/// One row of posters on the Home screen.
public struct HomeRow: Identifiable, Sendable {
    public var feed: HomeFeed
    public var series: [SeriesSummary]
    public var id: HomeFeed { feed }

    public init(feed: HomeFeed, series: [SeriesSummary]) {
        self.feed = feed
        self.series = series
    }
}

/// A server's block on the Home screen.
public struct HomeServerSection: Identifiable, Sendable {
    public var server: ServerConfig
    public var rows: [HomeRow]
    /// Set when every feed failed, e.g. the server is offline.
    public var errorMessage: String?
    public var id: UUID { server.id }

    public init(server: ServerConfig, rows: [HomeRow], errorMessage: String? = nil) {
        self.server = server
        self.rows = rows
        self.errorMessage = errorMessage
    }
}

/// What to load for one server on the Home screen.
public struct HomeSource: Sendable {
    public var server: MangaServer
    /// False when this profile doesn't sync progress to the server. The
    /// server's "Continue Reading" then belongs to someone else (Suwayomi
    /// has one progress per server), so `localContinueReading` is shown
    /// instead.
    public var includeContinueReading: Bool
    /// The profile's own Continue Reading for this server, from local
    /// progress. Used when `includeContinueReading` is false.
    public var localContinueReading: [SeriesSummary]

    public init(server: MangaServer, includeContinueReading: Bool = true, localContinueReading: [SeriesSummary] = []) {
        self.server = server
        self.includeContinueReading = includeContinueReading
        self.localContinueReading = localContinueReading
    }
}

public enum HomeLoader {
    /// Loads every server's feeds in parallel. Sections come back in the
    /// order of `sources`. Empty rows are dropped. A section only reports
    /// an error when none of its feeds loaded.
    public static func load(_ sources: [HomeSource], limit: Int = 20) async -> [HomeServerSection] {
        var sections = [HomeServerSection?](repeating: nil, count: sources.count)
        for await (index, section) in each(sources, limit: limit) { sections[index] = section }
        return sections.compactMap { $0 }
    }

    /// Loads every server's feeds in parallel and hands over each server's
    /// section as soon as it's ready, with its index in `sources`, so Home
    /// can show the fast servers without waiting for the slowest one.
    /// Cancelling the consuming task cancels the loads.
    public static func each(_ sources: [HomeSource], limit: Int = 20) -> AsyncStream<(Int, HomeServerSection)> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: (Int, HomeServerSection).self) { group in
                    for (index, source) in sources.enumerated() {
                        group.addTask { (index, await load(source, limit: limit)) }
                    }
                    for await result in group { continuation.yield(result) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func load(_ source: HomeSource, limit: Int = 20) async -> HomeServerSection {
        let feeds = HomeFeed.allCases.filter { $0 != .continueReading || source.includeContinueReading }
        let server = source.server
        let results = await withTaskGroup(of: (HomeFeed, Result<[SeriesSummary], Error>).self) { group in
            for feed in feeds {
                group.addTask {
                    do { return (feed, .success(try await server.feed(feed, limit: limit))) }
                    catch { return (feed, .failure(error)) }
                }
            }
            var out: [HomeFeed: Result<[SeriesSummary], Error>] = [:]
            for await (feed, result) in group { out[feed] = result }
            return out
        }
        var rows: [HomeRow] = []
        if !source.includeContinueReading, !source.localContinueReading.isEmpty {
            rows.append(HomeRow(feed: .continueReading, series: Array(source.localContinueReading.prefix(limit))))
        }
        var firstError: Error?
        for feed in feeds {
            switch results[feed] {
            case .success(let series)?:
                if !series.isEmpty { rows.append(HomeRow(feed: feed, series: series)) }
            case .failure(let error)?:
                firstError = firstError ?? error
            case nil:
                break
            }
        }
        let allFailed = !feeds.isEmpty && feeds.allSatisfy { if case .failure? = results[$0] { return true } else { return false } }
        return HomeServerSection(server: server.config, rows: rows,
                                 errorMessage: allFailed ? firstError.map(userMessage) : nil)
    }
}

/// Merges one Home feed from several servers into a single row.
public enum HomeMerge {
    /// `lists` holds each server's series for the feed, in server order,
    /// each list in the server's own order (newest first). The result keeps
    /// every server's order and interleaves the lists: when the next series
    /// of two servers both have a `feedDate`, the newer goes first;
    /// otherwise the one ranked higher on its own server goes first (ties
    /// go to the earlier server). The same series appears once.
    public static func merge(_ lists: [[SeriesSummary]], limit: Int? = nil) -> [SeriesSummary] {
        var heads = Array(repeating: 0, count: lists.count)
        var seen = Set<SeriesRef>()
        var result: [SeriesSummary] = []
        let total = lists.reduce(0) { $0 + $1.count }
        result.reserveCapacity(min(total, limit ?? total))
        while limit.map({ result.count < $0 }) ?? true {
            var best: Int?
            for i in lists.indices where heads[i] < lists[i].count {
                guard let b = best else { best = i; continue }
                if comesBefore(lists[i][heads[i]], rank: heads[i], lists[b][heads[b]], rank: heads[b]) { best = i }
            }
            guard let i = best else { break }
            let next = lists[i][heads[i]]
            heads[i] += 1
            if seen.insert(next.ref).inserted { result.append(next) }
        }
        return result
    }

    /// Whether `a` (from a later server than `b`) goes before `b`.
    static func comesBefore(_ a: SeriesSummary, rank ra: Int, _ b: SeriesSummary, rank rb: Int) -> Bool {
        if let da = a.feedDate, let db = b.feedDate, da != db { return da > db }
        return ra < rb
    }
}

/// Search results from one server.
public struct ServerSearchResults: Identifiable, Sendable {
    public var server: ServerConfig
    public var series: [SeriesSummary]
    public var errorMessage: String?
    public var id: UUID { server.id }

    public init(server: ServerConfig, series: [SeriesSummary], errorMessage: String? = nil) {
        self.server = server
        self.series = series
        self.errorMessage = errorMessage
    }
}

public enum CrossServerSearch {
    /// The query to send, or nil when there is nothing worth searching.
    /// Siri dictation ends sentences with a period or question mark and
    /// may wrap words in quotes, which would make the servers find nothing,
    /// so those are dropped from the ends.
    public static func normalize(_ query: String) -> String? {
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".。!！?？\"“”'‘’「」"))
        let trimmed = query.trimmingCharacters(in: edges)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Searches every server in parallel. Results keep the order of
    /// `servers`; servers with no matches and no error are left out.
    public static func run(_ query: String, on servers: [MangaServer]) async -> [ServerSearchResults] {
        guard let q = normalize(query) else { return [] }
        return await withTaskGroup(of: (Int, ServerSearchResults).self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    do {
                        return (index, ServerSearchResults(server: server.config, series: try await server.search(q)))
                    } catch {
                        return (index, ServerSearchResults(server: server.config, series: [], errorMessage: userMessage(error)))
                    }
                }
            }
            var out = [ServerSearchResults?](repeating: nil, count: servers.count)
            for await (index, result) in group { out[index] = result }
            return out.compactMap { $0 }.filter { !$0.series.isEmpty || $0.errorMessage != nil }
        }
    }
}

func userMessage(_ error: Error) -> String {
    ConnectionErrorText.message(for: error)
}
