import XCTest
@testable import MangaCore

final class ImageCachingTests: XCTestCase {
    let server = ImageStubServer()
    var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageCachingTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDiskCacheSurvivesANewPipeline() async throws {
        let transport = ImageTransport()
        let url = "http://k/api/Reader/image?chapterId=1&page=0&apiKey=topsecret"
        transport.serve(url, data: makePNG(width: 200, height: 300))

        let first = ImagePipeline(transport: transport, diskDirectory: directory)
        _ = try await first.load(URL(string: url)!, server: server, targetSize: nil)
        first.disk?.flush()

        let second = ImagePipeline(transport: transport, diskDirectory: directory)
        let image = try await second.load(URL(string: url)!, server: server, targetSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(image.pixelSize, PageSize(width: 200, height: 300))
        XCTAssertEqual(transport.count(url), 1, "second pipeline should read from disk")

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names.count, 1)
        XCTAssertFalse(names[0].contains("topsecret"))
        XCTAssertEqual(names[0].count, 64, "SHA-256 hex file name")
    }

    func testNonImageResponsesAreNotCachedOnDisk() async {
        let transport = ImageTransport()
        let url = "http://stub/login-page"
        transport.serve(url, data: Data("<html>login</html>".utf8))
        let pipeline = ImagePipeline(transport: transport, diskDirectory: directory)
        do { _ = try await pipeline.load(URL(string: url)!, server: server, targetSize: nil); XCTFail() } catch {
            XCTAssertEqual(error as? ImagePipelineError, .undecodable)
        }
        pipeline.disk?.flush()
        XCTAssertEqual(pipeline.diskUsage, 0)
    }

    func testDiskCacheTrimsOldestPastLimit() throws {
        let cache = DiskImageCache(directory: directory, limit: 1000)
        cache.store(Data(repeating: 1, count: 400), for: "a")
        cache.store(Data(repeating: 2, count: 400), for: "b")
        cache.flush()
        func age(_ key: String, _ seconds: TimeInterval) throws {
            let url = directory.appendingPathComponent(DiskImageCache.fileName(for: key))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -seconds)], ofItemAtPath: url.path)
        }
        try age("a", 3600)
        try age("b", 1800)
        // 1,200 bytes > 1,000: trims oldest-first down to 750.
        cache.store(Data(repeating: 3, count: 400), for: "c")
        cache.flush()
        XCTAssertEqual(cache.size, 400)
        XCTAssertNil(cache.data(for: "a"))
        XCTAssertNil(cache.data(for: "b"))
        XCTAssertNotNil(cache.data(for: "c"))
    }

    func testConcurrentLoadsShareOneDownload() async throws {
        let transport = ImageTransport()
        transport.delay = 200_000_000
        let url = URL(string: "http://stub/page/shared")!
        transport.serve(url.absoluteString, data: makePNG(width: 50, height: 80))
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil)
        let server = self.server

        async let a = pipeline.load(url, server: server, targetSize: CGSize(width: 64, height: 64))
        async let b = pipeline.load(url, server: server, targetSize: CGSize(width: 640, height: 640))
        async let c = pipeline.load(url, server: server, targetSize: nil)
        let results = try await [a, b, c]
        XCTAssertEqual(results.map(\.pixelSize), Array(repeating: PageSize(width: 50, height: 80), count: 3))
        XCTAssertEqual(transport.count(url.absoluteString), 1)
    }

    func testCancellingOneWaiterKeepsTheSharedDownload() async throws {
        let transport = ImageTransport()
        transport.delay = 300_000_000
        let url = URL(string: "http://stub/page/keep")!
        transport.serve(url.absoluteString, data: makePNG(width: 40, height: 60))
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil)
        let server = self.server

        let cancelled = Task { try await pipeline.load(url, server: server, targetSize: nil) }
        let kept = Task { try await pipeline.load(url, server: server, targetSize: CGSize(width: 32, height: 32)) }
        try await Task.sleep(nanoseconds: 50_000_000)
        cancelled.cancel()
        let image = try await kept.value
        XCTAssertEqual(image.pixelSize, PageSize(width: 40, height: 60))
        XCTAssertEqual(transport.count(url.absoluteString), 1)
    }

    func testDownloadsAreLimited() async throws {
        let transport = ImageTransport()
        transport.delay = 50_000_000
        let urls = (0..<8).map { URL(string: "http://stub/limit/\($0)")! }
        for u in urls { transport.serve(u.absoluteString, data: makePNG(width: 10, height: 10)) }
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil, maxConcurrentDownloads: 2)
        let server = self.server

        try await withThrowingTaskGroup(of: Void.self) { group in
            for u in urls { group.addTask { _ = try await pipeline.load(u, server: server, targetSize: nil) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(transport.requests.count, 8)
        XCTAssertLessThanOrEqual(transport.maxActive, 2)
    }

    func testPrefetchWithoutTargetReadsSizeOnly() async throws {
        let transport = ImageTransport()
        let url = URL(string: "http://stub/size-only")!
        transport.serve(url.absoluteString, data: makePNG(width: 1600, height: 900))
        let pipeline = ImagePipeline(transport: transport, diskDirectory: directory)

        let done = expectation(description: "size")
        pipeline.prefetch([url], server: server, targetSize: nil) { _, size in
            XCTAssertEqual(size, PageSize(width: 1600, height: 900))
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertNil(pipeline.cachedImage(for: url, targetSize: nil, scaling: .fit), "nothing decoded")
        pipeline.disk?.flush()
        XCTAssertGreaterThan(pipeline.diskUsage, 0)

        // The later load comes from disk.
        _ = try await pipeline.load(url, server: server, targetSize: CGSize(width: 960, height: 540))
        XCTAssertEqual(transport.count(url.absoluteString), 1)
    }

    func testDownloadLimiterPrefersVisibleRequests() async {
        let limiter = DownloadLimiter(limit: 1)
        await limiter.acquire(key: "busy", high: true)
        let order = OrderBox()
        let low = Task { await limiter.acquire(key: "low", high: false); order.append("low"); await limiter.release() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let high = Task { await limiter.acquire(key: "high", high: true); order.append("high"); await limiter.release() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await limiter.release()
        _ = await (low.value, high.value)
        XCTAssertEqual(order.values, ["high", "low"])
    }
}

final class OrderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
