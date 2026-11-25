import Foundation

/// The chapters currently loaded into the webtoon reader's strip, in reading
/// order. The strip grows as the reader nears either end (the next chapter
/// joins below, the previous one above) and drops chapters more than one
/// away from the one being read, so a long series never piles up in memory.
public struct WebtoonStrip: Hashable, Sendable {
    public struct Segment: Hashable, Sendable {
        public var chapter: Chapter
        public var pages: [PageDescriptor]
        public var sizes: [PageSize?]

        public init(chapter: Chapter, pages: [PageDescriptor], sizes: [Int: PageSize] = [:]) {
            self.chapter = chapter
            let ordered = pages.sorted { $0.index < $1.index }
            self.pages = ordered
            self.sizes = ordered.indices.map { i in sizes[i] ?? ordered[i].size }
        }

        public var id: String { chapter.id }
        public var layoutSegment: WebtoonSegment { WebtoonSegment(id: chapter.id, sizes: sizes) }

        /// Known sizes by page index, in the form `ReaderSession` uses.
        public var knownSizes: [Int: PageSize] {
            var result: [Int: PageSize] = [:]
            for (i, s) in sizes.enumerated() { if let s { result[i] = s } }
            return result
        }
    }

    public private(set) var segments: [Segment] = []

    public init(segments: [Segment] = []) {
        self.segments = segments
    }

    public var isEmpty: Bool { segments.isEmpty }
    public var first: Segment? { segments.first }
    public var last: Segment? { segments.last }

    public func segment(_ id: String) -> Segment? { segments.first { $0.id == id } }
    public func index(of id: String) -> Int? { segments.firstIndex { $0.id == id } }
    public func contains(_ id: String) -> Bool { index(of: id) != nil }

    public var layoutSegments: [WebtoonSegment] { segments.map(\.layoutSegment) }

    public mutating func reset(_ segment: Segment) { segments = [segment] }

    public mutating func append(_ segment: Segment) {
        guard !contains(segment.id) else { return }
        segments.append(segment)
    }

    public mutating func prepend(_ segment: Segment) {
        guard !contains(segment.id) else { return }
        segments.insert(segment, at: 0)
    }

    /// Records a page's real size. Returns true if it changed.
    @discardableResult
    public mutating func setSize(_ size: PageSize, segment id: String, page: Int) -> Bool {
        guard let s = index(of: id), segments[s].sizes.indices.contains(page),
              segments[s].sizes[page] != size else { return false }
        segments[s].sizes[page] = size
        return true
    }

    /// Drops chapters more than `keep` positions away from `id`. Returns
    /// the ids removed.
    @discardableResult
    public mutating func trim(around id: String, keep: Int = 1) -> [String] {
        guard let center = index(of: id) else { return [] }
        let lo = max(0, center - keep)
        let hi = min(segments.count - 1, center + keep)
        let removed = segments.enumerated().filter { $0.offset < lo || $0.offset > hi }.map(\.element.id)
        segments = Array(segments[lo...hi])
        return removed
    }

    /// Where a chapter sits in the series' chapter list.
    public static func neighbor(of chapterID: String, in chapters: [Chapter], offset: Int) -> Chapter? {
        guard let i = chapters.firstIndex(where: { $0.id == chapterID }) else { return nil }
        let j = i + offset
        return chapters.indices.contains(j) ? chapters[j] : nil
    }
}
