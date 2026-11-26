import Foundation

/// Puts a server's chapters in reading order (oldest first) when the server
/// gives an order that may run either way, may have gaps, or may have ties.
public enum ChapterOrdering {
    public struct Item: Sendable {
        /// The server's own position (Suwayomi `sourceOrder`), if any.
        public var sourceOrder: Int?
        /// The chapter number; negative means unknown.
        public var number: Double?
        public var name: String
        /// Last tie-break, so the result never depends on input order.
        public var id: Int

        public init(sourceOrder: Int?, number: Double?, name: String, id: Int) {
            self.sourceOrder = sourceOrder
            self.number = number
            self.name = name
            self.id = id
        }

        var knownNumber: Double? { number.flatMap { $0 >= 0 ? $0 : nil } }
    }

    /// - With server positions: sorted by them; if the chapter numbers mostly
    ///   go down along that order, the order is flipped. Chapters without a
    ///   position go last.
    /// - Without: by chapter number when every chapter has one, otherwise by
    ///   name in natural order ("Ch 2" before "Ch 10").
    /// Ties are broken by name (natural order), then id.
    public static func readingOrder<T>(_ elements: [T], locale: Locale? = .current, item: (T) -> Item) -> [T] {
        typealias Entry = (item: Item, name: NaturalSort.Key, element: T)
        let keyed: [Entry] = elements.map { element in
            let info = item(element)
            return (item: info, name: NaturalSort.Key(info.name, locale: locale), element: element)
        }

        func tieBreak(_ a: Entry, _ b: Entry) -> Bool {
            let r = a.name.compare(to: b.name)
            return r != .orderedSame ? r == .orderedAscending : a.item.id < b.item.id
        }

        if keyed.contains(where: { $0.item.sourceOrder != nil }) {
            func bySource(descending: Bool) -> [Entry] {
                keyed.sorted { a, b in
                    switch (a.item.sourceOrder, b.item.sourceOrder) {
                    case let (x?, y?) where x != y: return descending ? x > y : x < y
                    case (.some, nil): return true
                    case (nil, .some): return false
                    default: return tieBreak(a, b)
                    }
                }
            }
            let ascending = bySource(descending: false)
            let numbers = ascending.compactMap { $0.item.knownNumber }
            return (runsDown(numbers) ? bySource(descending: true) : ascending).map { $0.element }
        }

        if !keyed.isEmpty, keyed.allSatisfy({ $0.item.knownNumber != nil }) {
            return keyed.sorted { a, b in
                let (x, y) = (a.item.knownNumber ?? 0, b.item.knownNumber ?? 0)
                return x != y ? x < y : tieBreak(a, b)
            }.map { $0.element }
        }
        return keyed.sorted(by: tieBreak).map { $0.element }
    }

    /// True when more neighbouring pairs go down than up (a newest-first
    /// list), so one misnumbered chapter can't flip a whole series. On a
    /// tie, the first and last numbers decide.
    static func runsDown(_ numbers: [Double]) -> Bool {
        guard numbers.count >= 2 else { return false }
        var up = 0, down = 0
        for (a, b) in zip(numbers, numbers.dropFirst()) {
            if b > a { up += 1 } else if b < a { down += 1 }
        }
        if up != down { return down > up }
        return numbers.first! > numbers.last!
    }
}
