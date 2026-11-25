import Foundation

/// What kind of file a series or chapter is. Image content (manga, comics,
/// archives, and PDFs the server renders to pages) opens in the paged and
/// vertical readers; text content opens in the book reader.
public enum ContentFormat: String, Codable, CaseIterable, Sendable, Hashable {
    /// Page images: archives (cbz/cbr/zip), image folders, online chapters.
    case images
    /// A PDF. Kavita renders its pages to images, so it reads like images.
    case pdf
    /// An EPUB ebook, read as reflowable text.
    case epub
    /// Plain text, read as reflowable text.
    case text

    /// Opens in the book reader rather than the image readers.
    public var isText: Bool { self == .epub || self == .text }

    /// A short label for posters and chapter rows. Nil for images, so manga
    /// and comics look the same as always.
    public var badge: String? {
        switch self {
        case .images: return nil
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .text: return "TXT"
        }
    }

    /// Spelled out, for the series detail line.
    public var displayName: String {
        switch self {
        case .images: return "Images"
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .text: return "Text"
        }
    }

    /// SF Symbol for chapter rows.
    public var symbol: String {
        switch self {
        case .images: return "photo.on.rectangle"
        case .pdf: return "doc.richtext"
        case .epub: return "book"
        case .text: return "doc.plaintext"
        }
    }

    /// Kavita's `MangaFormat`: Image 0, Archive 1, Unknown 2, Epub 3, Pdf 4.
    public init?(kavitaFormat value: Int?) {
        switch value {
        case 0, 1: self = .images
        case 3: self = .epub
        case 4: self = .pdf
        default: return nil
        }
    }

    /// From a file name or OPDS link, by extension or MIME type.
    public init?(fileExtensionOrMIME raw: String) {
        let s = raw.lowercased()
        switch s {
        case "epub", "application/epub+zip": self = .epub
        case "pdf", "application/pdf": self = .pdf
        case "txt", "text/plain": self = .text
        case "cbz", "cbr", "cb7", "zip", "rar", "7z", "application/x-cbz", "application/x-cbr",
             "application/vnd.comicbook+zip", "application/vnd.comicbook-rar":
            self = .images
        default:
            if s.hasPrefix("image/") { self = .images } else { return nil }
        }
    }
}
