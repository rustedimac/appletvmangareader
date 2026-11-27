import Foundation

/// Home's rows as last loaded, and the `contentKey` they belong to.
///
/// It lives in the app model, not in the Home view: switching between a
/// theme and the default theme rebuilds every screen, and a Home that kept
/// its rows in view state came back empty, showing only the fastest source
/// (the built-in Free Library) until the servers answered again. Kept here,
/// a rebuilt Home shows its rows at once and refreshes them in place.
///
/// Rows only show for the key they were loaded for, so Home never mixes in
/// a removed server, an unticked library or another profile's rows.
public struct HomeSnapshot: Sendable {
    public private(set) var sections: [HomeServerSection] = []
    /// The `contentKey` that `sections` belong to.
    public private(set) var key: String?
    /// The key of the last reload that finished.
    public private(set) var loadedKey: String?
    /// Only the newest reload may change the rows.
    public private(set) var generation = 0

    public init() {}

    /// The rows for `key`, or none when they were loaded for another one.
    public func sections(for key: String) -> [HomeServerSection] {
        self.key == key ? sections : []
    }

    public func isLoaded(_ key: String) -> Bool { loadedKey == key }

    /// Starts a reload for `key` and the servers in `order`. Rows already
    /// loaded for the same key stay until their server answers again;
    /// rows for another key are dropped right away.
    public mutating func beginReload(key: String, order: [UUID]) -> HomeReload {
        generation += 1
        let previous = self.key == key
            ? Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            : [:]
        if previous.isEmpty {
            sections = []
            self.key = key
        }
        return HomeReload(generation: generation, key: key, order: order, previous: previous)
    }

    /// Whether `reload` is still the newest one.
    public func isCurrent(_ reload: HomeReload) -> Bool { reload.generation == generation }

    /// Puts one server's fresh section in, keeping server order. Ignored
    /// when a newer reload has started.
    public mutating func receive(_ section: HomeServerSection, in reload: inout HomeReload) {
        guard isCurrent(reload) else { return }
        reload.fresh[section.id] = section
        sections = reload.order.compactMap { reload.fresh[$0] ?? reload.previous[$0] }
        key = reload.key
    }

    /// Marks `reload` done. Ignored when a newer reload has started.
    public mutating func finish(_ reload: HomeReload) {
        guard isCurrent(reload) else { return }
        loadedKey = reload.key
    }
}

/// One Home reload in progress (see `HomeSnapshot.beginReload`).
public struct HomeReload: Sendable {
    public let generation: Int
    public let key: String
    let order: [UUID]
    let previous: [UUID: HomeServerSection]
    var fresh: [UUID: HomeServerSection] = [:]
}
