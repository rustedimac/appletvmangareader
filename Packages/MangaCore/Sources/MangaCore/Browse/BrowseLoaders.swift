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
    /// has one progress per server), so the row is left out.
    public var includeContinueReading: Bool

    public init(server: MangaServer, includeContinueReading: Bool = true) {
        self.server = server
        self.includeContinueReading = includeContinueReading
    }
}

public enum HomeLoader {
    /// Loads every server's feeds in parallel. Sections come back in the
    /// order of `sources`. Empty rows are dropped. A section only reports
    /// an error when none of its feeds loaded.
    public static func load(_ sources: [HomeSource], limit: Int = 20) async -> [HomeServerSection] {
        await withTaskGroup(of: (Int, HomeServerSection).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { (index, await load(source, limit: limit)) }
            }
            var sections = [HomeServerSection?](repeating: nil, count: sources.count)
            for await (index, section) in group { sections[index] = section }
            return sections.compactMap { $0 }
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
