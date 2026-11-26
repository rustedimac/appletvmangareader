import Foundation

/// Where a series is in its publication run. Each backend has its own
/// list; these are the states they share.
///
/// | Here | Kavita | Suwayomi | Komga |
/// | --- | --- | --- | --- |
/// | Ongoing | OnGoing | ONGOING | ONGOING |
/// | Completed | Completed, Ended | COMPLETED, PUBLISHING_FINISHED | ENDED |
/// | Hiatus | Hiatus | ON_HIATUS | HIATUS |
/// | Cancelled | Cancelled | CANCELLED | ABANDONED |
public enum PublicationStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case ongoing
    case completed
    case hiatus
    case cancelled

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ongoing: return "Ongoing"
        case .completed: return "Completed"
        case .hiatus: return "On Hiatus"
        case .cancelled: return "Cancelled"
        }
    }

    /// Suwayomi's `MangaStatus`. LICENSED and UNKNOWN have no match, so a
    /// status filter leaves those series out.
    public init?(suwayomi raw: String?) {
        switch raw?.uppercased() {
        case "ONGOING": self = .ongoing
        case "COMPLETED", "PUBLISHING_FINISHED": self = .completed
        case "ON_HIATUS": self = .hiatus
        case "CANCELLED": self = .cancelled
        default: return nil
        }
    }

    /// Kavita's `PublicationStatus` values for this state.
    public var kavitaValues: [Int] {
        switch self {
        case .ongoing: return [0]
        case .hiatus: return [1]
        // Ended is "finished, but the library lacks some issues".
        case .completed: return [2, 4]
        case .cancelled: return [3]
        }
    }

    /// Komga's `SeriesMetadata.Status`.
    public var komgaValue: String {
        switch self {
        case .ongoing: return "ONGOING"
        case .completed: return "ENDED"
        case .hiatus: return "HIATUS"
        case .cancelled: return "ABANDONED"
        }
    }
}

/// How much of a series the profile has read, for the library filter.
public enum ReadProgressFilter: String, Codable, CaseIterable, Sendable, Identifiable {
    case any
    /// Nothing read yet.
    case unread
    /// Started, not finished.
    case inProgress
    /// Unread or in progress: anything with chapters left to read.
    case unfinished
    /// Every chapter read.
    case read

    public static let `default` = ReadProgressFilter.any

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: return "Any"
        case .unread: return "Not Started"
        case .inProgress: return "In Progress"
        case .unfinished: return "Not Finished"
        case .read: return "Finished"
        }
    }

    /// Whether a series with `unread` of `total` chapters (or pages) left
    /// passes. A series with no count passes only `any`; one with nothing
    /// in it counts as unread.
    public func matches(unread: Int?, total: Int?) -> Bool {
        if self == .any { return true }
        guard let unread, let total else { return false }
        let left = min(max(unread, 0), max(total, 0))
        switch self {
        case .any: return true
        case .unread: return total == 0 || left == total
        case .inProgress: return left > 0 && left < total
        case .unfinished: return total == 0 || left > 0
        case .read: return total > 0 && left == 0
        }
    }
}

/// Which filters a backend can apply to a library grid. The Sort & View
/// screen offers only these, and a filter's other parts are ignored for
/// that server (`LibraryFilter.limited(to:)`).
public struct LibraryFilterSupport: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let status = LibraryFilterSupport(rawValue: 1 << 0)
    public static let readProgress = LibraryFilterSupport(rawValue: 1 << 1)
    public static let genres = LibraryFilterSupport(rawValue: 1 << 2)

    public static let all: LibraryFilterSupport = [.status, .readProgress, .genres]
}

/// Narrows a library grid. Empty sets mean "any". Within one part the
/// choices are alternatives (Ongoing or Hiatus; Romance or Comedy); the
/// parts combine (Ongoing and Not Finished).
public struct LibraryFilter: Codable, Hashable, Sendable {
    public var statuses: Set<PublicationStatus>
    public var readProgress: ReadProgressFilter
    /// Genre names as the server spells them. Matched without regard to
    /// case or accents.
    public var genres: Set<String>

    public static let empty = LibraryFilter()

    public init(statuses: Set<PublicationStatus> = [], readProgress: ReadProgressFilter = .any,
                genres: Set<String> = []) {
        self.statuses = statuses
        self.readProgress = readProgress
        self.genres = genres
    }

    private enum CodingKeys: String, CodingKey { case statuses, readProgress, genres }

    /// Unknown statuses or read choices from a newer build are dropped
    /// rather than failing the profile's browse settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawStatuses = (try? c.decodeIfPresent([String].self, forKey: .statuses)) ?? []
        statuses = Set(rawStatuses.compactMap(PublicationStatus.init(rawValue:)))
        let rawRead = (try? c.decodeIfPresent(String.self, forKey: .readProgress)) ?? nil
        readProgress = rawRead.flatMap(ReadProgressFilter.init(rawValue:)) ?? .any
        genres = Set((try? c.decodeIfPresent([String].self, forKey: .genres)) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !statuses.isEmpty { try c.encode(statuses.map(\.rawValue).sorted(), forKey: .statuses) }
        if readProgress != .any { try c.encode(readProgress.rawValue, forKey: .readProgress) }
        if !genres.isEmpty { try c.encode(genres.sorted(), forKey: .genres) }
    }

    public var isEmpty: Bool { statuses.isEmpty && readProgress == .any && genres.isEmpty }

    /// A stable string for this filter, for view identity and `.task(id:)`.
    public var key: String {
        let status = statuses.map(\.rawValue).sorted().joined(separator: ",")
        let genre = genres.map(Self.fold).sorted().joined(separator: ",")
        return "s:\(status);r:\(readProgress.rawValue);g:\(genre)"
    }

    /// How many parts are set, for the "2 filters" label.
    public var activeCount: Int {
        (statuses.isEmpty ? 0 : 1) + (readProgress == .any ? 0 : 1) + (genres.isEmpty ? 0 : 1)
    }

    /// A short description: "Everything", or e.g. "Ongoing or On Hiatus,
    /// Not Finished, Comedy".
    public var summary: String {
        var parts: [String] = []
        if !statuses.isEmpty {
            parts.append(PublicationStatus.allCases.filter(statuses.contains).map(\.title).joined(separator: " or "))
        }
        if readProgress != .any { parts.append(readProgress.title) }
        if !genres.isEmpty { parts.append(Self.genreList(genres).joined(separator: " or ")) }
        return parts.isEmpty ? "Everything" : parts.joined(separator: ", ")
    }

    /// Only the parts `support` covers.
    public func limited(to support: LibraryFilterSupport) -> LibraryFilter {
        LibraryFilter(statuses: support.contains(.status) ? statuses : [],
                      readProgress: support.contains(.readProgress) ? readProgress : .any,
                      genres: support.contains(.genres) ? genres : [])
    }

    /// The parts a whole-library default may set. Genres are left out:
    /// each library has its own genre list.
    public var forDefault: LibraryFilter {
        LibraryFilter(statuses: statuses, readProgress: readProgress)
    }

    /// For backends that filter on the client. Nil status, read counts or
    /// genres fail the parts that need them.
    public func matches(status: PublicationStatus?, unread: Int?, total: Int?, genres seriesGenres: [String]?) -> Bool {
        if !statuses.isEmpty {
            guard let status, statuses.contains(status) else { return false }
        }
        if !readProgress.matches(unread: unread, total: total) { return false }
        if !genres.isEmpty {
            let wanted = Set(genres.map(Self.fold))
            guard let seriesGenres, seriesGenres.contains(where: { wanted.contains(Self.fold($0)) }) else { return false }
        }
        return true
    }

    /// Case-, accent- and space-insensitive form of a genre name.
    public static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Genre names from many series: each once (first spelling wins),
    /// in natural order.
    public static func genreList<S: Sequence>(_ names: S) -> [String] where S.Element == String {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(fold(trimmed)).inserted else { continue }
            out.append(trimmed)
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// The profile's library settings for every library that hasn't set its
/// own (Settings > Library Defaults). A library's own value in
/// `LibraryOptions` overrides each of these; nil there means "use this".
public struct LibraryDefaults: Codable, Hashable, Sendable {
    public var sort: LibrarySort
    public var gridOrder: GridOrder
    /// Status and read progress only (see `LibraryFilter.forDefault`).
    public var filter: LibraryFilter

    public static let `default` = LibraryDefaults()

    public init(sort: LibrarySort = .default, gridOrder: GridOrder = .automatic, filter: LibraryFilter = .empty) {
        self.sort = sort
        self.gridOrder = gridOrder
        self.filter = filter.forDefault
    }

    private enum CodingKeys: String, CodingKey { case sort, gridOrder, filter }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sort = (try? c.decodeIfPresent(LibrarySort.self, forKey: .sort)) ?? .default
        gridOrder = (try? c.decodeIfPresent(GridOrder.self, forKey: .gridOrder)) ?? .automatic
        let decoded: LibraryFilter? = (try? c.decodeIfPresent(LibraryFilter.self, forKey: .filter)) ?? nil
        filter = (decoded ?? LibraryFilter.empty).forDefault
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if sort != .default { try c.encode(sort, forKey: .sort) }
        if gridOrder != .automatic { try c.encode(gridOrder, forKey: .gridOrder) }
        if !filter.isEmpty { try c.encode(filter, forKey: .filter) }
    }

    public var isDefault: Bool { self == .default }
}
