import Foundation

/// Kavita's age ratings (`API/Entities/Enums/AgeRating.cs`). Raw values are
/// Kavita's, so "at most Teen" is `rawValue <= 8`, the same comparison
/// Kavita's own filters use. Suwayomi has no age ratings.
public enum AgeRating: Int, Codable, CaseIterable, Comparable, Sendable, Identifiable {
    case notApplicable = -1
    case unknown = 0
    case ratingPending = 1
    case earlyChildhood = 2
    case everyone = 3
    case g = 4
    case everyone10Plus = 5
    case pg = 6
    case kidsToAdults = 7
    case teen = 8
    case mature15Plus = 9
    case mature17Plus = 10
    case mature = 11
    case r18Plus = 12
    case adultsOnly = 13
    case x18Plus = 14

    public var id: Int { rawValue }

    public static func < (a: AgeRating, b: AgeRating) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .notApplicable: return "Not Applicable"
        case .unknown: return "Unknown"
        case .ratingPending: return "Rating Pending"
        case .earlyChildhood: return "Early Childhood"
        case .everyone: return "Everyone"
        case .g: return "G"
        case .everyone10Plus: return "Everyone 10+"
        case .pg: return "PG"
        case .kidsToAdults: return "Kids to Adults"
        case .teen: return "Teen"
        case .mature15Plus: return "Mature 15+"
        case .mature17Plus: return "Mature 17+"
        case .mature: return "Mature"
        case .r18Plus: return "R18+"
        case .adultsOnly: return "Adults Only 18+"
        case .x18Plus: return "X18+"
        }
    }

    /// Ratings at or below this count as "no rating".
    public static let unratedCeiling: AgeRating = .ratingPending

    public var isUnrated: Bool { self <= Self.unratedCeiling }

    /// The limits offered in the profile's content settings, mildest first.
    public static let limitChoices: [AgeRating] = [.earlyChildhood, .everyone, .everyone10Plus, .teen,
                                                   .mature15Plus, .mature17Plus, .adultsOnly]
}

/// What a profile is not allowed to see, on every server. Libraries and
/// categories are chosen per server (`ProfileServerSettings.selectedCategoryIDs`);
/// this covers what cuts across servers: genres, tags and an age limit.
///
/// Genre and tag names are matched without regard to case, accents or
/// surrounding spaces, so hiding "Horror" also hides "horror".
public struct ContentFilter: Codable, Hashable, Sendable {
    /// Genres to hide, as their display names.
    public var hiddenGenres: Set<String>
    /// Tags to hide (Kavita only; Suwayomi has genres only).
    public var hiddenTags: Set<String>
    /// The highest age rating shown, or nil for no limit (Kavita only).
    public var maxAgeRating: AgeRating?
    /// With an age limit, also hide series that have no rating. Most
    /// libraries have no ratings unless ComicInfo.xml sets them, so this is
    /// off by default.
    public var hideUnrated: Bool

    public init(hiddenGenres: Set<String> = [], hiddenTags: Set<String> = [], maxAgeRating: AgeRating? = nil,
                hideUnrated: Bool = false) {
        self.hiddenGenres = hiddenGenres
        self.hiddenTags = hiddenTags
        self.maxAgeRating = maxAgeRating
        self.hideUnrated = hideUnrated
    }

    public static let none = ContentFilter()

    enum CodingKeys: String, CodingKey {
        case hiddenGenres, hiddenTags, maxAgeRating, hideUnrated
    }

    /// Tolerant, like all saved data (see `TolerantDecoding.swift`): a
    /// missing field or an age rating from a newer build falls back
    /// instead of losing the filter.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiddenGenres = Set(c.tolerantArray(.hiddenGenres) as [String])
        hiddenTags = Set(c.tolerantArray(.hiddenTags) as [String])
        // An age limit this build can't read (from a newer build, say)
        // becomes the strictest one, never "no limit".
        if c.contains(.maxAgeRating), (try? c.decodeNil(forKey: .maxAgeRating)) != true {
            maxAgeRating = c.tolerant(.maxAgeRating) ?? AgeRating.allCases.min()
        } else {
            maxAgeRating = nil
        }
        hideUnrated = c.tolerant(.hideUnrated, default: false)
    }

    /// False when the filter hides nothing.
    public var isActive: Bool {
        !hiddenGenres.isEmpty || !hiddenTags.isEmpty || maxAgeRating != nil
    }

    /// Matching key for a genre or tag name.
    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    var hiddenGenreKeys: Set<String> { Set(hiddenGenres.map(Self.normalize)) }
    var hiddenTagKeys: Set<String> { Set(hiddenTags.map(Self.normalize)) }

    public func isGenreHidden(_ name: String) -> Bool { hiddenGenreKeys.contains(Self.normalize(name)) }
    public func isTagHidden(_ name: String) -> Bool { hiddenTagKeys.contains(Self.normalize(name)) }

    /// Hides or shows a genre, keeping one entry per normalized name.
    public mutating func setGenre(_ name: String, hidden: Bool) {
        let key = Self.normalize(name)
        hiddenGenres = hiddenGenres.filter { Self.normalize($0) != key }
        if hidden && !key.isEmpty { hiddenGenres.insert(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    public mutating func setTag(_ name: String, hidden: Bool) {
        let key = Self.normalize(name)
        hiddenTags = hiddenTags.filter { Self.normalize($0) != key }
        if hidden && !key.isEmpty { hiddenTags.insert(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Whether the age rating alone hides a series. `nil` means the server
    /// has no rating for it (treated like Unknown).
    public func hidesRating(_ rating: AgeRating?) -> Bool {
        guard let max = maxAgeRating else { return false }
        let r = rating ?? .unknown
        if r.isUnrated { return hideUnrated }
        return r > max
    }

    /// Whether a series with this metadata is hidden. Pass nil for an age
    /// rating the server doesn't have.
    public func hides(genres: [String], tags: [String] = [], ageRating: AgeRating? = nil,
                      supportsAgeRating: Bool = true) -> Bool {
        let genreKeys = hiddenGenreKeys
        if !genreKeys.isEmpty, genres.contains(where: { genreKeys.contains(Self.normalize($0)) }) { return true }
        let tagKeys = hiddenTagKeys
        if !tagKeys.isEmpty, tags.contains(where: { tagKeys.contains(Self.normalize($0)) }) { return true }
        return supportsAgeRating && hidesRating(ageRating)
    }

    /// A stable string for cache keys and `.task(id:)`.
    public var cacheKey: String {
        guard isActive else { return "none" }
        let g = hiddenGenreKeys.sorted().joined(separator: ",")
        let t = hiddenTagKeys.sorted().joined(separator: ",")
        let a = maxAgeRating.map { "\($0.rawValue)\(hideUnrated ? "u" : "")" } ?? "-"
        return "g:\(g)|t:\(t)|a:\(a)"
    }

    /// One line for Settings: "Hides 2 genres, 1 tag · Up to Teen".
    public var summary: String {
        guard isActive else { return "Everything is shown" }
        var parts: [String] = []
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        var hidden: [String] = []
        if !hiddenGenres.isEmpty { hidden.append(count(hiddenGenres.count, "genre")) }
        if !hiddenTags.isEmpty { hidden.append(count(hiddenTags.count, "tag")) }
        if !hidden.isEmpty { parts.append("Hides " + hidden.joined(separator: ", ")) }
        if let max = maxAgeRating { parts.append("Up to \(max.title)") }
        return parts.joined(separator: " · ")
    }
}

/// The genres and tags a server knows about, for the filter checklist.
public struct ContentFacets: Hashable, Sendable {
    public var genres: [String]
    public var tags: [String]
    /// Whether series on this server carry age ratings (Kavita).
    public var supportsAgeRating: Bool

    public init(genres: [String] = [], tags: [String] = [], supportsAgeRating: Bool = false) {
        self.genres = genres
        self.tags = tags
        self.supportsAgeRating = supportsAgeRating
    }

    /// Facets from several servers, merged: one entry per normalized name,
    /// sorted by name. Names already hidden by `filter` are kept even when
    /// no server reports them anymore, so they can be shown again.
    public static func merged(_ all: [ContentFacets], keeping filter: ContentFilter = .none) -> ContentFacets {
        func merge(_ lists: [[String]], _ keep: Set<String>) -> [String] {
            var byKey: [String: String] = [:]
            for name in lists.joined() + keep.sorted() {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = ContentFilter.normalize(trimmed)
                guard !key.isEmpty, byKey[key] == nil else { continue }
                byKey[key] = trimmed
            }
            return byKey.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return ContentFacets(genres: merge(all.map(\.genres), filter.hiddenGenres),
                             tags: merge(all.map(\.tags), filter.hiddenTags),
                             supportsAgeRating: all.contains(where: \.supportsAgeRating))
    }
}

/// Which series to leave out of lists that come from local data (Favorites,
/// Top Shelf) rather than from a filtered server client.
public enum ContentVisibility {
    /// Drops series the filter hides. `hidden` maps a server id to the ids
    /// `MangaServer.hiddenSeriesIDs(for:)` returned. With an active filter, a
    /// server missing from `hidden` (not loaded yet, or offline) hides all of
    /// its series: the filter fails closed.
    public static func visible(_ series: [SeriesSummary], filter: ContentFilter,
                               hidden: [UUID: Set<String>]) -> [SeriesSummary] {
        guard filter.isActive else { return series }
        return series.filter { s in
            guard let ids = hidden[s.ref.serverID] else { return false }
            return !ids.contains(s.ref.seriesID)
        }
    }
}
