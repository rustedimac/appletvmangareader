import Foundation

// Komga REST API shapes (verified against Komga 1.30.2). Only the fields the
// app reads are decoded; everything is optional where Komga may omit it.

/// Spring's `Page<T>` wrapper. `number` is zero-based.
struct KomgaPage<T: Decodable>: Decodable {
    var content: [T]
    var last: Bool?
    var number: Int?
    var totalElements: Int?
}

struct KomgaUserDTO: Decodable {
    var id: String
    var email: String?
    var roles: [String]?
}

struct KomgaActuatorInfoDTO: Decodable {
    struct Build: Decodable { var version: String? }
    var build: Build?
}

struct KomgaLibraryDTO: Decodable {
    var id: String
    var name: String
    var unavailable: Bool?
}

struct KomgaSeriesDTO: Decodable {
    struct Metadata: Decodable {
        var title: String?
        var summary: String?
        var status: String?
        var readingDirection: String?
        var genres: [String]?
        var tags: [String]?
    }
    struct BooksMetadata: Decodable {
        var authors: [KomgaAuthorDTO]?
        var summary: String?
    }
    var id: String
    var libraryId: String?
    var name: String
    var booksCount: Int?
    var booksUnreadCount: Int?
    var booksInProgressCount: Int?
    var metadata: Metadata?
    var booksMetadata: BooksMetadata?
    var created: Date?
    var lastModified: Date?
    var deleted: Bool?
    var oneshot: Bool?
}

struct KomgaAuthorDTO: Decodable {
    var name: String
    var role: String?
}

struct KomgaBookDTO: Decodable {
    struct Media: Decodable {
        var status: String?
        var mediaType: String?
        var pagesCount: Int?
        /// DIVINA (images), PDF or EPUB.
        var mediaProfile: String?
        var epubDivinaCompatible: Bool?
    }
    struct Metadata: Decodable {
        var title: String?
        var number: String?
        var numberSort: Double?
        var authors: [KomgaAuthorDTO]?
    }
    struct ReadProgress: Decodable {
        /// One-based page.
        var page: Int
        var completed: Bool
        var readDate: Date?
        var lastModified: Date?
    }
    var id: String
    var seriesId: String
    var seriesTitle: String?
    var libraryId: String?
    var name: String
    var number: Double?
    var lastModified: Date?
    var media: Media?
    var metadata: Metadata?
    var readProgress: ReadProgress?
    var deleted: Bool?
    var oneshot: Bool?
}

struct KomgaPageDTO: Decodable {
    /// One-based.
    var number: Int
    var fileName: String?
    var mediaType: String?
    var width: Double?
    var height: Double?
}

/// Body of `PATCH api/v1/books/{id}/read-progress`. `page` is one-based.
struct KomgaReadProgressUpdate: Encodable {
    var page: Int?
    var completed: Bool?
}

/// Body of `POST api/v1/series/list` and `api/v1/books/list` (Komga 1.19+).
struct KomgaSearch: Encodable {
    var condition: KomgaCondition?
    var fullTextSearch: String?
}

/// A Komga search condition, e.g. `{"libraryId": {"operator": "is", "value": "…"}}`,
/// combined with `anyOf` / `allOf`.
indirect enum KomgaCondition: Encodable, Equatable {
    case `is`(field: String, value: String)
    case anyOf([KomgaCondition])
    case allOf([KomgaCondition])

    /// Nil for no conditions, the condition itself for one, else `anyOf`.
    static func any(_ conditions: [KomgaCondition]) -> KomgaCondition? {
        conditions.count <= 1 ? conditions.first : .anyOf(conditions)
    }

    static func all(_ conditions: [KomgaCondition?]) -> KomgaCondition? {
        let present = conditions.compactMap { $0 }
        return present.count <= 1 ? present.first : .allOf(present)
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct Operator: Encodable {
        var `operator` = "is"
        var value: String
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .is(let field, let value): try c.encode(Operator(value: value), forKey: Key(field))
        case .anyOf(let list): try c.encode(list, forKey: Key("anyOf"))
        case .allOf(let list): try c.encode(list, forKey: Key("allOf"))
        }
    }
}
