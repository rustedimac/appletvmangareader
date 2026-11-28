import XCTest
@testable import MangaCore

final class ImageDecoderTests: XCTestCase {
    func testMaxPixelSizeFitUsesTighterSide() {
        let page = PageSize(width: 1000, height: 1500)
        // 1080 tall screen: height is the limit.
        XCTAssertEqual(ImageDecoder.maxPixelSize(original: page, target: CGSize(width: 1920, height: 1080), scaling: .fit), 1080)
    }

    func testMaxPixelSizeFillUsesLooserSide() {
        let cover = PageSize(width: 1000, height: 1000)
        // Fill a 200 × 300 poster: needs 300 px on both sides.
        XCTAssertEqual(ImageDecoder.maxPixelSize(original: cover, target: CGSize(width: 200, height: 300), scaling: .fill), 300)
    }

    func testMaxPixelSizeNeverUpscalesAndHandlesUnconstrained() {
        let page = PageSize(width: 800, height: 1200)
        XCTAssertEqual(ImageDecoder.maxPixelSize(original: page, target: CGSize(width: 4000, height: 4000), scaling: .fit), 1200)
        XCTAssertEqual(ImageDecoder.maxPixelSize(original: page, target: nil, scaling: .fit), 1200)
        // Webtoon: width-constrained only.
        XCTAssertEqual(ImageDecoder.maxPixelSize(original: page, target: CGSize(width: 400, height: 0), scaling: .fit), 600)
        XCTAssertEqual(ImageDecoder.maxPixelSize(original: page, target: CGSize(width: 400, height: CGFloat.infinity), scaling: .fit), 600)
    }

    func testMaxPixelSizeCapsAtTextureLimit() {
        let strip = PageSize(width: 800, height: 40_000)
        XCTAssertEqual(ImageDecoder.maxPixelSize(original: strip, target: nil, scaling: .fit), ImageDecoder.maxTextureSide)
    }

    func testDecodeDownsamplesAndReportsOriginalSize() throws {
        let data = makePNG(width: 400, height: 1200)
        XCTAssertEqual(ImageDecoder.pixelSize(of: data), PageSize(width: 400, height: 1200))
        let image = try ImageDecoder.decode(data, targetSize: CGSize(width: 100, height: 100), scaling: .fit)
        XCTAssertEqual(image.pixelSize, PageSize(width: 400, height: 1200))
        XCTAssertEqual(image.cgImage.height, 100)
        XCTAssertLessThanOrEqual(image.cgImage.width, 34)
    }

    /// Codex (and Komga without an image Accept header) answer a PDF
    /// book's page with a one-page PDF. It's drawn instead of failing with
    /// "The page isn't an image the TV can show".
    func testDecodesAPageSentAsAPDF() throws {
        let data = makePDF(width: 300, height: 450)
        XCTAssertEqual(ImageDecoder.pixelSize(of: data), PageSize(width: 1600, height: 2400))
        let image = try ImageDecoder.decode(data, targetSize: CGSize(width: 1920, height: 1080), scaling: .fit)
        XCTAssertEqual(image.pixelSize, PageSize(width: 1600, height: 2400))
        XCTAssertEqual(image.cgImage.height, 1080)
        XCTAssertEqual(image.cgImage.width, 720)
    }

    func testDecodeRejectsNonImages() {
        XCTAssertThrowsError(try ImageDecoder.decode(Data("<html>".utf8), targetSize: nil, scaling: .fit)) {
            XCTAssertEqual($0 as? ImagePipelineError, .undecodable)
        }
    }
}

final class ImagePipelineTests: XCTestCase {
    let server = ImageStubServer()

    func testLoadAuthorizesAndCachesInMemory() async throws {
        let transport = ImageTransport()
        let url = "http://stub/api/v1/manga/1/chapter/1/page/0"
        transport.serve(url, data: makePNG(width: 300, height: 450))
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil)

        let first = try await pipeline.load(URL(string: url)!, server: server, targetSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(first.pixelSize, PageSize(width: 300, height: 450))
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Basic dGVzdDp0ZXN0")

        _ = try await pipeline.load(URL(string: url)!, server: server, targetSize: CGSize(width: 1900, height: 1070))
        XCTAssertEqual(transport.count(url), 1, "same 64 px bucket should hit the memory cache")
        XCTAssertNotNil(pipeline.cachedImage(for: URL(string: url)!, targetSize: CGSize(width: 1920, height: 1080), scaling: .fit))
        XCTAssertEqual(pipeline.cachedPixelSize(for: URL(string: url)!), PageSize(width: 300, height: 450))
    }

    func testHTTPErrorsMapToMangaError() async {
        let transport = ImageTransport()
        transport.serve("http://stub/denied", status: 401, data: Data())
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil)
        do { _ = try await pipeline.load(URL(string: "http://stub/missing")!, server: server, targetSize: nil); XCTFail() } catch {
            XCTAssertEqual(error as? MangaError, .notFound)
        }
        do { _ = try await pipeline.load(URL(string: "http://stub/denied")!, server: server, targetSize: nil); XCTFail() } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
    }

    func testCacheKeyIgnoresKavitaAPIKey() {
        let a = URL(string: "http://k/api/Reader/image?chapterId=5&page=2&apiKey=secret1")!
        let b = URL(string: "http://k/api/Reader/image?chapterId=5&page=2&apiKey=secret2")!
        XCTAssertEqual(ImagePipeline.cacheKey(a), ImagePipeline.cacheKey(b))
        XCTAssertFalse(ImagePipeline.cacheKey(a).contains("secret"))
        XCTAssertEqual(ImagePipeline.cacheKey(URL(string: "http://s/p?x=1")!), "http://s/p?x=1")
    }

    func testPrefetchReportsPixelSizes() async throws {
        let transport = ImageTransport()
        let urls = (0..<3).map { "http://stub/page/\($0)" }
        for (i, u) in urls.enumerated() { transport.serve(u, data: makePNG(width: 100 + i, height: 200)) }
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil)

        let got = expectation(description: "sizes")
        got.expectedFulfillmentCount = 3
        let sizes = SizeBox()
        pipeline.prefetch(urls.map { URL(string: $0)! }, server: server, targetSize: CGSize(width: 500, height: 500)) { url, size in
            sizes.set(url.absoluteString, size)
            got.fulfill()
        }
        await fulfillment(of: [got], timeout: 5)
        XCTAssertEqual(sizes.get("http://stub/page/2"), PageSize(width: 102, height: 200))
        XCTAssertEqual(pipeline.cachedPixelSize(for: URL(string: urls[1])!), PageSize(width: 101, height: 200))
    }
}

final class SizeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: PageSize] = [:]
    func set(_ k: String, _ v: PageSize) { lock.lock(); values[k] = v; lock.unlock() }
    func get(_ k: String) -> PageSize? { lock.lock(); defer { lock.unlock() }; return values[k] }
}
