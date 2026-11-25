import Foundation

/// The "which libraries to import" checklist: a server's Kavita libraries or
/// Suwayomi categories and which of them are ticked. Pure value type so the
/// rules are unit tested; the server editor and the library picker own one
/// in `@State`.
public struct CategorySelection: Equatable, Sendable {
    /// Every library/category on the server, in display order.
    public private(set) var available: [MangaCategory]
    public private(set) var selected: Set<String>

    /// `saved` is the stored setting: nil ticks everything. Saved ids that
    /// are no longer on the server are dropped.
    public init(available: [MangaCategory], saved: Set<String>?) {
        self.available = available.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        let ids = Set(self.available.map(\.id))
        self.selected = saved.map { $0.intersection(ids) } ?? ids
    }

    public func isSelected(_ id: String) -> Bool { selected.contains(id) }

    public mutating func toggle(_ id: String) {
        guard available.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public mutating func set(_ id: String, _ on: Bool) {
        if on != isSelected(id) { toggle(id) }
    }

    public mutating func selectAll() { selected = Set(available.map(\.id)) }
    public mutating func selectNone() { selected = [] }

    public var allSelected: Bool { selected.count == available.count }

    /// At least one has to be ticked, or the server would show nothing.
    public var canSave: Bool { !selected.isEmpty || available.isEmpty }

    /// What to store in `ProfileServerSettings.selectedCategoryIDs`: nil when
    /// everything is ticked, so libraries added to the server later show up
    /// too; otherwise exactly the ticked ids.
    public var storedValue: Set<String>? {
        allSelected ? nil : selected
    }

    /// "All 4 libraries", "2 of 4 categories".
    public func summary(kind: ServerKind) -> String {
        let noun: String
        switch kind {
        case .kavita: noun = available.count == 1 ? "library" : "libraries"
        case .suwayomi: noun = available.count == 1 ? "category" : "categories"
        }
        if available.isEmpty { return "No \(kind == .kavita ? "libraries" : "categories")" }
        if allSelected { return available.count == 1 ? "1 \(noun)" : "All \(available.count) \(noun)" }
        return "\(selected.count) of \(available.count) \(noun)"
    }
}

public extension ServerKind {
    /// "Libraries" for Kavita, "Categories" for Suwayomi.
    var categoryNoun: String {
        switch self {
        case .kavita: return "Libraries"
        case .suwayomi: return "Categories"
        }
    }
}
