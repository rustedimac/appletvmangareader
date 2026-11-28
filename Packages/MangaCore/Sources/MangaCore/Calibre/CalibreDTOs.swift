import Foundation

/// `GET ajax/library-info`.
struct CalibreLibraryInfoDTO: Decodable {
    var libraryMap: [String: String]
    var defaultLibrary: String?

    enum CodingKeys: String, CodingKey {
        case libraryMap = "library_map"
        case defaultLibrary = "default_library"
    }
}

/// `GET ajax/search/<library>`: book ids only.
struct CalibreSearchDTO: Decodable {
    var totalNum: Int
    var offset: Int?
    var num: Int?
    var bookIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case totalNum = "total_num"
        case offset, num
        case bookIDs = "book_ids"
    }
}

/// One book from `GET ajax/books/<library>?ids=…`. Only the fields the app
/// uses; dates stay strings because Calibre writes "undefined" dates as
/// year 101.
struct CalibreBookDTO: Decodable, Sendable {
    var id: Int
    var title: String
    var titleSort: String?
    var authors: [String]
    var series: String?
    var seriesIndex: Double?
    var tags: [String]
    var formats: [String]
    var comments: String?
    var timestamp: String?
    var lastModified: String?
    var cover: String?
    var thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id = "application_id"
        case title
        case titleSort = "title_sort"
        case authors, series
        case seriesIndex = "series_index"
        case tags, formats, comments, timestamp
        case lastModified = "last_modified"
        case cover, thumbnail
    }

    init(id: Int, title: String, titleSort: String? = nil, authors: [String] = [], series: String? = nil,
         seriesIndex: Double? = nil, tags: [String] = [], formats: [String] = [], comments: String? = nil,
         timestamp: String? = nil, lastModified: String? = nil, cover: String? = nil, thumbnail: String? = nil) {
        self.id = id
        self.title = title
        self.titleSort = titleSort
        self.authors = authors
        self.series = series
        self.seriesIndex = seriesIndex
        self.tags = tags
        self.formats = formats
        self.comments = comments
        self.timestamp = timestamp
        self.lastModified = lastModified
        self.cover = cover
        self.thumbnail = thumbnail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Filled in from the response's key when missing.
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? -1
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Untitled"
        titleSort = try? c.decodeIfPresent(String.self, forKey: .titleSort)
        authors = (try? c.decodeIfPresent([String].self, forKey: .authors)) ?? []
        series = (try? c.decodeIfPresent(String.self, forKey: .series)).flatMap { $0?.isEmpty == false ? $0 : nil }
        seriesIndex = try? c.decodeIfPresent(Double.self, forKey: .seriesIndex)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        formats = (try? c.decodeIfPresent([String].self, forKey: .formats)) ?? []
        comments = try? c.decodeIfPresent(String.self, forKey: .comments)
        timestamp = try? c.decodeIfPresent(String.self, forKey: .timestamp)
        lastModified = try? c.decodeIfPresent(String.self, forKey: .lastModified)
        cover = try? c.decodeIfPresent(String.self, forKey: .cover)
        thumbnail = try? c.decodeIfPresent(String.self, forKey: .thumbnail)
    }

    var added: Date? { timestamp.flatMap(Self.date) }
    var modified: Date? { lastModified.flatMap(Self.date) }

    /// Calibre's "undefined" date is year 101; treat anything before 1900
    /// as unknown.
    static func date(_ s: String) -> Date? {
        guard let d = DateParsing.parse(s), d > Date(timeIntervalSince1970: -2_208_988_800) else { return nil }
        return d
    }
}
