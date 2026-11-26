import Foundation

/// Where the book reader is: a section, and a screen page inside it.
/// Page counts per section are only known once a section is laid out
/// (they depend on the font size and screen), so the cursor works with
/// whatever counts are known and asks for a section when it needs one.
public struct BookCursor: Hashable, Sendable {
    public var section: Int
    public var page: Int

    public init(section: Int = 0, page: Int = 0) {
        self.section = section
        self.page = page
    }

    public enum Move: Equatable, Sendable {
        /// Moved within the laid-out pages.
        case moved
        /// Needs this section laid out first. `toEnd` means open it on its
        /// last page (moving backwards).
        case needsSection(Int, toEnd: Bool)
        /// Already at the very start or end of the book.
        case atStart
        case atEnd
    }

    /// One screen forward. `pageCounts[s]` is the number of screen pages in
    /// section `s`, when it has been laid out.
    public mutating func forward(pageCounts: [Int: Int], sectionCount: Int) -> Move {
        if let count = pageCounts[section], page + 1 < count {
            page += 1
            return .moved
        }
        // Skip sections that laid out to nothing (blank spine items).
        var next = section + 1
        while next < sectionCount, pageCounts[next] == 0 { next += 1 }
        guard next < sectionCount else { return .atEnd }
        guard pageCounts[next] != nil else { return .needsSection(next, toEnd: false) }
        section = next
        page = 0
        return .moved
    }

    public mutating func backward(pageCounts: [Int: Int]) -> Move {
        if page > 0 {
            page -= 1
            return .moved
        }
        var previous = section - 1
        while previous >= 0, pageCounts[previous] == 0 { previous -= 1 }
        guard previous >= 0 else { return .atStart }
        guard let count = pageCounts[previous] else { return .needsSection(previous, toEnd: true) }
        section = previous
        page = max(0, count - 1)
        return .moved
    }

    /// How far into the current section this page starts, 0..<1. Stored so
    /// a book reopens on the same text after the font size or screen
    /// changes the page count.
    public func fraction(pageCount: Int) -> Double {
        guard pageCount > 1 else { return 0 }
        return Double(min(page, pageCount - 1)) / Double(pageCount)
    }

    /// The page in a section of `pageCount` pages that holds `fraction`.
    public static func page(forFraction fraction: Double, pageCount: Int) -> Int {
        guard pageCount > 1, fraction > 0 else { return 0 }
        // Nudge up so a fraction saved from page k maps back to page k.
        return min(pageCount - 1, max(0, Int((fraction * Double(pageCount) + 1e-6).rounded(.down))))
    }

    /// Finished when on the last page of the last non-empty section.
    public func isAtEnd(pageCounts: [Int: Int], sectionCount: Int) -> Bool {
        guard let count = pageCounts[section], page >= count - 1 else { return false }
        var next = section + 1
        while next < sectionCount, pageCounts[next] == 0 { next += 1 }
        return next >= sectionCount
    }
}

/// A saved place in a book: section plus how far into it.
public struct BookPosition: Codable, Hashable, Sendable {
    public var section: Int
    public var fraction: Double
    public var updatedAt: Date

    public init(section: Int, fraction: Double, updatedAt: Date = Date()) {
        self.section = section
        self.fraction = fraction
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case section, fraction, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        section = try c.decode(Int.self, forKey: .section)
        fraction = c.tolerant(.fraction, default: 0)
        updatedAt = c.tolerant(.updatedAt, default: .distantPast)
    }
}

/// Keeps the in-section position for books, per profile. Servers only
/// store the section (Kavita's page number), so without this a long
/// chapter would reopen at its start. Capped so it stays small in
/// UserDefaults.
public final class BookPositionStore: @unchecked Sendable {
    public static let key = "mangareader.bookpositions.v1"
    public static let limit = 200

    private let backing: KeyValueStore
    private let lock = NSLock()
    private var cache: [String: BookPosition]?

    public init(backing: KeyValueStore) {
        self.backing = backing
    }

    static func storageKey(profile: UUID, chapter: Chapter) -> String {
        "\(profile.uuidString)|\(chapter.seriesRef.storageKey)|\(chapter.id)"
    }

    public func position(profile: UUID, chapter: Chapter) -> BookPosition? {
        lock.lock(); defer { lock.unlock() }
        return load()[Self.storageKey(profile: profile, chapter: chapter)]
    }

    public func setPosition(_ position: BookPosition?, profile: UUID, chapter: Chapter) {
        lock.lock(); defer { lock.unlock() }
        var all = load()
        all[Self.storageKey(profile: profile, chapter: chapter)] = position
        if all.count > Self.limit {
            let keep = all.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(Self.limit)
            all = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        cache = all
        backing.set(try? JSONEncoder().encode(all), forKey: Self.key)
    }

    private func load() -> [String: BookPosition] {
        if let cache { return cache }
        let decoded = backing.data(forKey: Self.key).map(Self.decode) ?? [:]
        cache = decoded
        return decoded
    }

    /// Saved positions, skipping any entry that can't be read so one bad
    /// entry doesn't lose every book's place.
    static func decode(_ data: Data) -> [String: BookPosition] {
        let raw = (try? JSONDecoder().decode([String: Lossy<BookPosition>].self, from: data)) ?? [:]
        return raw.compactMapValues(\.value)
    }

    /// Where to open a book chapter: the server's (or local) section, and
    /// the saved fraction only if it was saved for that same section.
    public static func resume(chapter: Chapter, saved: BookPosition?, sectionCount: Int) -> (section: Int, fraction: Double) {
        let last = max(0, sectionCount - 1)
        if chapter.isRead { return (0, 0) }
        let section = min(max(0, chapter.lastPageRead), last)
        if let saved, saved.section == section { return (section, saved.fraction) }
        return (section, 0)
    }
}
