import Foundation

/// State for an infinitely scrolling list that loads one page at a time
/// (a library category's poster grid). Pure value type so the paging rules
/// are unit tested; the view owns it in `@State` and runs the fetch.
///
/// Usage:
/// ```
/// guard let ticket = pager.beginLoad() else { return }
/// do { pager.finish(ticket, try await fetch(ticket.page)) }
/// catch { pager.fail(ticket, error) }
/// ```
public struct LibraryPager<Item: Identifiable & Sendable>: Sendable where Item.ID: Sendable {
    /// Identifies one in-flight request, so a response that arrives after
    /// `reset()` is ignored.
    public struct Ticket: Equatable, Sendable {
        public let page: Int
        let generation: Int
    }

    public private(set) var items: [Item] = []
    public private(set) var hasMore = true
    public private(set) var isLoading = false
    /// The last load's error message. Cleared by `retry()` or `reset()`.
    public private(set) var errorMessage: String?
    public let pageSize: Int
    /// Start loading the next page when the user is this many items from
    /// the end.
    public let prefetchDistance: Int

    private var nextPage = 1
    private var generation = 0
    private var seen: Set<Item.ID> = []

    public init(pageSize: Int = 48, prefetchDistance: Int = 18) {
        self.pageSize = max(1, pageSize)
        self.prefetchDistance = max(0, prefetchDistance)
    }

    /// True before the first page has come back.
    public var isInitialLoad: Bool { items.isEmpty && (isLoading || (hasMore && errorMessage == nil)) }

    /// True when every page has loaded and there was nothing.
    public var isEmpty: Bool { items.isEmpty && !hasMore && errorMessage == nil }

    /// Returns the page to fetch, or nil if a load is running, everything
    /// is loaded, or the last load failed (call `retry()` first).
    public mutating func beginLoad() -> Ticket? {
        guard hasMore, !isLoading, errorMessage == nil else { return nil }
        isLoading = true
        return Ticket(page: nextPage, generation: generation)
    }

    /// Appends a page. Items already shown are skipped, since servers can
    /// shift items between pages while the user scrolls.
    public mutating func finish(_ ticket: Ticket, _ page: Paged<Item>) {
        guard ticket.generation == generation else { return }
        isLoading = false
        for item in page.items where seen.insert(item.id).inserted {
            items.append(item)
        }
        nextPage = ticket.page + 1
        hasMore = page.hasMore && !page.items.isEmpty
    }

    public mutating func fail(_ ticket: Ticket, _ error: Error) {
        fail(ticket, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    public mutating func fail(_ ticket: Ticket, message: String) {
        guard ticket.generation == generation else { return }
        isLoading = false
        errorMessage = message
    }

    /// Clears the error so the next `beginLoad()` tries the same page again.
    public mutating func retry() {
        errorMessage = nil
    }

    /// Starts over from page 1 and drops any request in flight.
    public mutating func reset() {
        generation += 1
        items = []
        seen = []
        nextPage = 1
        hasMore = true
        isLoading = false
        errorMessage = nil
    }

    /// Whether showing the item at `index` should trigger the next page.
    public func shouldLoadMore(afterShowing index: Int) -> Bool {
        hasMore && !isLoading && errorMessage == nil && index >= items.count - 1 - prefetchDistance
    }
}
