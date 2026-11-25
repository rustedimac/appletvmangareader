import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers the Free Library's JSON requests offline, for UI tests
/// (`-uiTesting -freeLibrary`) and previews: an IIIF manifest with
/// `pagesPerItem` portrait canvases for any identifier, and a two-episode
/// Pepper&Carrot list. Only the JSON is canned; it carries no artwork.
public struct FreeLibraryDemoTransport: HTTPTransport {
    public var pagesPerItem: Int

    public init(pagesPerItem: Int = 8) {
        self.pagesPerItem = pagesPerItem
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let body: String?
        if url.host == "iiif.archive.org", url.path.hasSuffix("/manifest.json") {
            let id = url.pathComponents.dropLast().last ?? "item"
            body = manifest(for: id)
        } else if url == PepperCarrot.episodesURL {
            body = """
                [{"name": "ep01_Potion-of-Flight", "total_pages": 4, "translated_languages": ["en", "fr"]},
                 {"name": "ep02_Rainbow-potions", "total_pages": 6, "translated_languages": ["en", "fr"]}]
                """
        } else {
            body = nil
        }
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        return (Data((body ?? "").utf8), response)
    }

    func manifest(for id: String) -> String {
        let canvases = (0..<pagesPerItem).map { i in
            let service = "https://iiif.archive.org/image/iiif/3/\(id)%2Fpage_\(i).jp2"
            return """
                {"type": "Canvas", "width": 1600, "height": 2400, "items": [{"type": "AnnotationPage", "items": [
                  {"type": "Annotation", "motivation": "painting", "body": {"id": "\(service)/full/max/0/default.jpg",
                   "type": "Image", "format": "image/jpeg", "service": [{"id": "\(service)", "type": "ImageService3"}]}}]}]}
                """
        }
        return #"{"type": "Manifest", "items": ["# + canvases.joined(separator: ",") + "]}"
    }
}
