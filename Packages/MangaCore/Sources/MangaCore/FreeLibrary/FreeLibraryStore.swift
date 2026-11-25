import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Holds the Free Library catalog and caches what the client fetches
/// (Pepper&Carrot's episode list, IIIF manifests). One instance is shared by
/// every `FreeLibraryClient`, so profiles and scoped copies reuse it.
///
/// `catalog()` never waits on the network: it answers with the best copy it
/// has (memory, then the copy saved in Caches, then the bundled one) and
/// starts a refresh from GitHub in the background when the copy is stale.
public actor FreeLibraryStore {
    public static let shared = FreeLibraryStore()

    private let bundled: FreeLibraryCatalog
    private let remoteURL: URL?
    private let cacheFile: URL?
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date

    private var current: FreeLibraryCatalog
    private var checkedAt: Date?
    private var refreshTask: Task<Void, Never>?

    private var episodes: (list: [PepperCarrotEpisode], at: Date)?
    private var manifests: [String: [PageDescriptor]] = [:]
    private var manifestOrder: [String] = []

    /// `remoteURL` nil turns off remote updates (UI tests). `cacheFile` nil
    /// keeps the fetched catalog in memory only.
    public init(bundled: FreeLibraryCatalog = .bundled,
                remoteURL: URL? = FreeLibrary.remoteCatalogURL,
                cacheFile: URL? = FreeLibraryStore.defaultCacheFile,
                maxAge: TimeInterval = 6 * 3600,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.bundled = bundled
        self.remoteURL = remoteURL
        self.cacheFile = cacheFile
        self.maxAge = maxAge
        self.now = now
        var best = bundled
        if let cacheFile, let data = try? Data(contentsOf: cacheFile),
           let saved = try? FreeLibraryCatalog.decode(data), Self.accepts(saved, over: bundled) {
            best = saved
        }
        self.current = best
    }

    public static var defaultCacheFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreeLibrary/catalog.json")
    }

    /// A remote catalog is used only if it is valid and not older.
    static func accepts(_ candidate: FreeLibraryCatalog, over existing: FreeLibraryCatalog) -> Bool {
        candidate.problems.isEmpty && candidate.version >= existing.version
    }

    /// The catalog to show now. Kicks off a background refresh if stale.
    public func catalog(transport: HTTPTransport) -> FreeLibraryCatalog {
        if remoteURL != nil, refreshTask == nil, checkedAt.map({ now().timeIntervalSince($0) > maxAge }) ?? true {
            refreshTask = Task { await self.refresh(transport: transport) }
        }
        return current
    }

    /// Fetches the remote catalog and adopts it if acceptable. Tests await
    /// this directly; the app lets `catalog(transport:)` start it.
    public func refresh(transport: HTTPTransport) async {
        defer { refreshTask = nil; checkedAt = now() }
        guard let remoteURL else { return }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let result = try? await transport.send(request), result.1.statusCode == 200,
              let remote = try? FreeLibraryCatalog.decode(result.0), Self.accepts(remote, over: bundled) else { return }
        let data = result.0
        guard remote != current else { return }
        current = remote
        if let cacheFile {
            try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheFile, options: .atomic)
        }
    }

    // MARK: Fetch caches

    func cachedEpisodes(maxAge: TimeInterval = 3600) -> [PepperCarrotEpisode]? {
        guard let episodes, now().timeIntervalSince(episodes.at) < maxAge else { return nil }
        return episodes.list
    }

    func storeEpisodes(_ list: [PepperCarrotEpisode]) {
        episodes = (list, now())
    }

    func cachedPages(_ key: String) -> [PageDescriptor]? { manifests[key] }

    /// Keeps the last 20 manifests (a chapter list and the next chapter).
    func storePages(_ pages: [PageDescriptor], for key: String) {
        manifests[key] = pages
        manifestOrder.removeAll { $0 == key }
        manifestOrder.append(key)
        while manifestOrder.count > 20 { manifests[manifestOrder.removeFirst()] = nil }
    }
}
