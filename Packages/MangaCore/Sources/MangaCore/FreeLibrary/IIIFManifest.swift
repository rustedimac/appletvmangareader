import Foundation

/// The parts of an Internet Archive IIIF Presentation 3 manifest the reader
/// needs: each canvas's size and its image service.
/// `https://iiif.archive.org/iiif/3/<identifier>/manifest.json`
struct IIIFManifest: Decodable {
    var type: String?
    var items: [Canvas]?

    struct Canvas: Decodable {
        var width: Double?
        var height: Double?
        var items: [AnnotationPage]?
    }

    struct AnnotationPage: Decodable {
        var items: [Annotation]?
    }

    struct Annotation: Decodable {
        var body: OneOrMany<Body>?
    }

    struct Body: Decodable {
        var id: String?
        var type: String?
        var width: Double?
        var height: Double?
        var service: OneOrMany<Service>?
    }

    struct Service: Decodable {
        var id: String?
        var legacyID: String?
        var type: String?

        enum CodingKeys: String, CodingKey {
            case id
            case legacyID = "@id"
            case type
        }

        var resolvedID: String? { id ?? legacyID }
    }

    /// IIIF allows a single object or an array in several places.
    struct OneOrMany<T: Decodable>: Decodable {
        var values: [T]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let many = try? container.decode([T].self) {
                values = many
            } else {
                values = [try container.decode(T.self)]
            }
        }
    }

    /// Widest image the reader asks for. Big enough for a full-height page
    /// on a 4K TV without fetching multi-megabyte originals.
    static let maxRequestWidth = 2048

    /// The IIIF size path for a page. A canvas's width isn't always the
    /// image's real width (Internet Archive sometimes reports double), and
    /// asking for more than the real width is an error, so: `max` for
    /// canvases up to `maxRequestWidth`, and a percentage, which can only
    /// shrink, above it.
    static func sizeParameter(canvasWidth: Double?) -> String {
        guard let width = canvasWidth, width > Double(maxRequestWidth) else { return "max" }
        let percent = (Double(maxRequestWidth) / width * 1000).rounded(.down) / 10
        return "pct:\(percent)"
    }

    /// One page per canvas, with its size known up front so spreads pair
    /// before images load. Only https archive.org URLs are returned.
    func pages() -> [PageDescriptor] {
        var pages: [PageDescriptor] = []
        for canvas in items ?? [] {
            guard let body = canvas.items?.first?.items?.first?.body?.values.first(where: { $0.type == nil || $0.type == "Image" }) else {
                continue
            }
            let width = canvas.width ?? body.width
            let height = canvas.height ?? body.height
            let url: URL?
            if let service = body.service?.values.first?.resolvedID {
                let base = service.hasSuffix("/") ? String(service.dropLast()) : service
                url = URL(string: "\(base)/full/\(Self.sizeParameter(canvasWidth: body.width ?? width))/0/default.jpg")
            } else {
                url = body.id.flatMap(URL.init(string:))
            }
            guard let url, Self.isArchiveURL(url) else { continue }
            let size = (width ?? 0) > 0 && (height ?? 0) > 0 ? PageSize(width: width!, height: height!) : nil
            pages.append(PageDescriptor(index: pages.count, url: url, size: size))
        }
        return pages
    }

    static func isArchiveURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "archive.org" || host.hasSuffix(".archive.org")
    }
}
