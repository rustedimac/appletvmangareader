import Foundation
import CoreGraphics
import ImageIO
@testable import MangaCore

/// A solid-colour PNG of the given size.
func makePNG(width: Int, height: Int) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = ctx.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

/// Serves image bytes by URL and counts requests.
final class ImageTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: (Int, Data)] = [:]
    private(set) var requests: [URLRequest] = []
    /// Delay before each response, to test overlapping requests.
    var delay: UInt64 = 0

    func serve(_ url: String, status: Int = 200, data: Data) {
        lock.lock(); responses[url] = (status, data); lock.unlock()
    }

    func count(_ url: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.url?.absoluteString == url }.count
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        requests.append(request)
        let hit = responses[request.url!.absoluteString]
        let delay = self.delay
        lock.unlock()
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        let (status, data) = hit ?? (404, Data())
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// A server that only knows how to authorize image requests.
struct ImageStubServer: MangaServer {
    var config = ServerConfig(kind: .suwayomi, name: "Stub", baseURL: URL(string: "http://stub")!)

    func validate() async throws -> String { "stub" }
    func categories() async throws -> [MangaCategory] { [] }
    func series(in category: MangaCategory, page: Int, pageSize: Int) async throws -> Paged<SeriesSummary> { Paged(items: [], hasMore: false) }
    func feed(_ feed: HomeFeed, limit: Int) async throws -> [SeriesSummary] { [] }
    func search(_ query: String) async throws -> [SeriesSummary] { [] }
    func seriesDetail(_ seriesID: String) async throws -> SeriesDetail { throw MangaError.notFound }
    func pages(for chapter: Chapter) async throws -> [PageDescriptor] { [] }
    func saveProgress(chapter: Chapter, libraryID: String?, page: Int, completed: Bool) async throws {}

    func authorize(_ request: URLRequest) -> URLRequest {
        var r = request
        r.setValue("Basic dGVzdDp0ZXN0", forHTTPHeaderField: "Authorization")
        return r
    }
}
