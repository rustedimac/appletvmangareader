import Foundation

// Minimal subsets of Kavita's API DTOs. Every field is optional where the
// server might omit it, so version drift doesn't break decoding.

struct KavitaUserDTO: Decodable {
    var username: String?
    var token: String?
    var refreshToken: String?
    /// The user's OPDS auth key.
    var apiKey: String?
    /// Every auth key on the account (Kavita 0.9+).
    var authKeys: [KavitaAuthKeyDTO]?
}

struct KavitaLoginDTO: Encodable {
    var username: String
    var password: String
}

/// `AuthKeyDto`.
struct KavitaAuthKeyDTO: Decodable {
    var key: String
    var name: String
    var expiresAtUtc: Date?

    func isExpired(now: Date) -> Bool {
        guard let expiresAtUtc else { return false }
        return expiresAtUtc <= now
    }
}

/// `RotateAuthKeyRequestDto`, for `api/Account/create-auth-key`. No
/// `expiresUtc` means the key never expires.
struct KavitaCreateAuthKeyDTO: Encodable {
    var keyLength: Int
    var name: String
    var expiresUtc: String?
}

struct KavitaLibraryDTO: Decodable {
    var id: Int
    var name: String
    var type: Int?
}

struct KavitaSeriesDTO: Decodable {
    var id: Int
    var name: String
    var localizedName: String?
    var pages: Int?
    var pagesRead: Int?
    var libraryId: Int?
    var libraryName: String?
    var created: Date?
    var lastChapterAdded: Date?
    /// `MangaFormat`: Image 0, Archive 1, Unknown 2, Epub 3, Pdf 4.
    var format: Int?
}

struct KavitaRecentlyUpdatedDTO: Decodable {
    var seriesId: Int
    var seriesName: String?
    var libraryId: Int?
    var created: Date?
}

struct KavitaSearchResultGroupDTO: Decodable {
    var series: [KavitaSearchSeriesDTO]?
}

struct KavitaSearchSeriesDTO: Decodable {
    var seriesId: Int
    var name: String
    var libraryId: Int?
    var format: Int?
}

struct KavitaPersonDTO: Decodable {
    var name: String
}

/// `GenreTagDto`. Series metadata and `api/Metadata/genres` both send
/// `id`; older fixtures only `title`.
struct KavitaGenreDTO: Decodable {
    var id: Int?
    var title: String
}

struct KavitaSeriesMetadataDTO: Decodable {
    var summary: String?
    var genres: [KavitaGenreDTO]?
    var writers: [KavitaPersonDTO]?
    var publicationStatus: Int?
}

struct KavitaChapterDTO: Decodable {
    var id: Int
    var range: String?
    var minNumber: Double?
    var sortOrder: Double?
    var pages: Int?
    var pagesRead: Int?
    var isSpecial: Bool?
    var title: String?
    var titleName: String?
    var volumeId: Int?
    var created: Date?
    var lastModifiedUtc: Date?
    var lastReadingProgressUtc: Date?
    var files: [KavitaMangaFileDTO]?
}

/// The file behind a chapter. Only the format is read; the path stays on
/// the server.
struct KavitaMangaFileDTO: Decodable {
    var format: Int?
}

struct KavitaVolumeDTO: Decodable {
    var id: Int
    var minNumber: Double?
    var name: String?
    var chapters: [KavitaChapterDTO]?
}

struct KavitaFileDimensionDTO: Decodable {
    var width: Double
    var height: Double
    var pageNumber: Int
    var isWide: Bool?
}

struct KavitaProgressDTO: Encodable {
    var volumeId: Int
    var chapterId: Int
    var pageNum: Int
    var seriesId: Int
    var libraryId: Int
}

/// `MarkReadDto`, for `api/Reader/mark-unread`.
struct KavitaMarkSeriesDTO: Encodable {
    var seriesId: Int
}

/// `MarkVolumesReadDto`, for `api/Reader/mark-multiple-unread`.
struct KavitaMarkMultipleDTO: Encodable {
    var seriesId: Int
    var volumeIds: [Int]
    var chapterIds: [Int]
}

/// Kavita's FilterV2Dto. Field/comparison values mirror Kavita's enums.
struct KavitaFilterV2: Encodable {
    struct Statement: Encodable {
        var comparison: Int
        var field: Int
        var value: String
    }

    struct SortOptions: Encodable {
        var sortField: Int
        var isAscending: Bool
    }

    var statements: [Statement] = []
    /// 0 = Or, 1 = And
    var combination: Int = 1
    var sortOptions: SortOptions? = nil
    var limitTo: Int = 0

    /// `FilterField`.
    enum Field {
        static let publicationStatus = 2
        static let genres = 18
        static let libraries = 19
        static let readProgress = 20
    }

    /// `FilterComparison`.
    enum Comparison {
        static let equal = 0
        static let greaterThan = 1
        static let lessThan = 3
        static let contains = 5
    }

    /// Series in any of these libraries.
    static func libraries(_ ids: [Int]) -> Statement {
        Statement(comparison: Comparison.contains, field: Field.libraries,
                  value: ids.map(String.init).joined(separator: ","))
    }

    enum Sort {
        static let sortName = 1
        static let createdDate = 2
        static let lastChapterAdded = 4
    }
}

/// Kavita PublicationStatus enum.
enum KavitaPublicationStatus {
    static func name(_ value: Int?) -> String? {
        switch value {
        case 0: return "Ongoing"
        case 1: return "Hiatus"
        case 2: return "Completed"
        case 3: return "Cancelled"
        case 4: return "Ended"
        default: return nil
        }
    }
}

/// Kavita shows users an OPDS URL like `http://host/api/opds/<apiKey>`.
/// Accepting that URL in the add-server form saves typing the key on a TV.
public enum KavitaOPDS {
    public struct Parsed: Equatable, Sendable {
        public var baseURL: URL
        public var apiKey: String
    }

    public static func parse(_ string: String) -> Parsed? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), components.scheme != nil, components.host != nil else {
            return nil
        }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let opdsIndex = parts.lastIndex(where: { $0.lowercased() == "opds" }),
              opdsIndex >= 1, parts[opdsIndex - 1].lowercased() == "api",
              opdsIndex + 1 < parts.count else { return nil }
        let key = parts[opdsIndex + 1]
        guard !key.isEmpty else { return nil }
        var base = components
        base.query = nil
        base.fragment = nil
        let prefix = parts[..<(opdsIndex - 1)]
        base.path = prefix.isEmpty ? "" : "/" + prefix.joined(separator: "/")
        guard let url = base.url else { return nil }
        return Parsed(baseURL: url, apiKey: key)
    }
}

/// `api/Book/{chapterId}/book-info`.
struct KavitaBookInfoDTO: Decodable {
    var bookTitle: String?
    var seriesName: String?
    var chapterTitle: String?
    var pages: Int?
    var seriesFormat: Int?
}

/// `api/Book/{chapterId}/chapters`: one table-of-contents entry.
struct KavitaBookChapterItemDTO: Decodable {
    var title: String?
    var part: String?
    var page: Int?
    var children: [KavitaBookChapterItemDTO]?
}
