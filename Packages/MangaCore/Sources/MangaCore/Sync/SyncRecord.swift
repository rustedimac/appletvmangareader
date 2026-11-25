import Foundation

/// What a synced record holds. A string, not an enum, so a record written by
/// a newer app version (say, bookmarks from a future iPhone app) survives a
/// round trip through an older one that doesn't know the kind yet.
public struct SyncKind: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let server = SyncKind("server")
    public static let profile = SyncKind("profile")
    public static let serverSettings = SyncKind("serverSettings")
    public static let favorite = SyncKind("favorite")
    public static let progress = SyncKind("progress")
    public static let readerDefaults = SyncKind("readerDefaults")
    public static let readerOverride = SyncKind("readerOverride")
}

/// One synced piece of state, e.g. one favorite or one series' progress.
/// The unit of merging: two devices that change different records never
/// conflict.
///
/// `key` is `"<kind>/<id>"`, unique across kinds. A nil `payload` is a
/// deletion (a tombstone), kept so other devices learn about it.
public struct SyncRecord: Codable, Hashable, Sendable {
    public var key: String
    public var kind: SyncKind
    /// Canonical JSON of the value (see `SyncMapper`), or nil when deleted.
    public var payload: Data?
    /// When this value was last changed on the device that changed it. The
    /// newest change wins (progress merges per chapter, see `SyncMerge`).
    public var modifiedAt: Date
    /// The device that made the change. Breaks ties between equal timestamps.
    public var deviceID: String

    public init(key: String, kind: SyncKind, payload: Data?, modifiedAt: Date, deviceID: String) {
        self.key = key
        self.kind = kind
        self.payload = payload
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
    }

    public var isDeleted: Bool { payload == nil }

    public static func key(_ kind: SyncKind, _ id: String) -> String { "\(kind.rawValue)/\(id)" }

    /// The id part of the key (after `"<kind>/"`).
    public var id: String { String(key.dropFirst(kind.rawValue.count + 1)) }
}

/// Read state of one chapter, with when it was set, so "read on the Apple TV"
/// and "marked unread on the phone" merge chapter by chapter.
public struct ReadMark: Codable, Hashable, Sendable {
    public var read: Bool
    public var at: Date

    public init(read: Bool, at: Date) {
        self.read = read
        self.at = at
    }
}

/// How a series' progress travels between devices. The position (chapter
/// and page) is last-writer-wins by `positionAt`; read chapters merge one by
/// one by their marks. Unread marks are kept so an "unread" survives a
/// device that still has the chapter as read.
public struct SyncedProgress: Codable, Hashable, Sendable {
    public var chapterID: String
    public var page: Int
    public var positionAt: Date
    public var marks: [String: ReadMark]

    public init(chapterID: String, page: Int, positionAt: Date, marks: [String: ReadMark] = [:]) {
        self.chapterID = chapterID
        self.page = page
        self.positionAt = positionAt
        self.marks = marks
    }

    public var readChapterIDs: Set<String> { Set(marks.filter { $0.value.read }.keys) }
}
