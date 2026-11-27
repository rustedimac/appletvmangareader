import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MangaCore

final class RetryPolicyTests: XCTestCase {
    private let noWait: @Sendable (TimeInterval) async throws -> Void = { _ in }

    func testDelaysGrowAndAreCapped() {
        let p = RetryPolicy(maxAttempts: 5, attemptTimeout: 10, initialDelay: 1, multiplier: 2, maxDelay: 3)
        XCTAssertEqual(p.delay(beforeRetry: 1), 1)
        XCTAssertEqual(p.delay(beforeRetry: 2), 2)
        XCTAssertEqual(p.delay(beforeRetry: 3), 3)
        XCTAssertEqual(p.delay(beforeRetry: 4), 3)
    }

    func testRetryableErrors() {
        XCTAssertTrue(RetryPolicy.isRetryable(URLError(.timedOut)))
        XCTAssertTrue(RetryPolicy.isRetryable(URLError(.networkConnectionLost)))
        XCTAssertTrue(RetryPolicy.isRetryable(URLError(.cannotConnectToHost)))
        XCTAssertTrue(RetryPolicy.isRetryable(MangaError.http(status: 503, body: "")))
        XCTAssertTrue(RetryPolicy.isRetryable(MangaError.http(status: 429, body: "")))
        XCTAssertTrue(RetryPolicy.isRetryable(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
        XCTAssertFalse(RetryPolicy.isRetryable(URLError(.cancelled)))
        XCTAssertFalse(RetryPolicy.isRetryable(CancellationError()))
        XCTAssertFalse(RetryPolicy.isRetryable(MangaError.unauthorized))
        XCTAssertFalse(RetryPolicy.isRetryable(MangaError.notFound))
        XCTAssertFalse(RetryPolicy.isRetryable(MangaError.http(status: 400, body: "")))
        XCTAssertFalse(RetryPolicy.isRetryable(ImagePipelineError.undecodable))
    }

    func testRetriesUntilSuccess() async throws {
        let counter = AttemptCounter()
        let p = RetryPolicy(maxAttempts: 3, attemptTimeout: 5)
        let value = try await p.run(sleep: noWait) { attempt -> Int in
            await counter.bump()
            if attempt < 3 { throw URLError(.networkConnectionLost) }
            return attempt
        }
        XCTAssertEqual(value, 3)
        let count = await counter.value
        XCTAssertEqual(count, 3)
    }

    func testGivesUpAfterMaxAttemptsWithLastError() async {
        let counter = AttemptCounter()
        let p = RetryPolicy(maxAttempts: 2, attemptTimeout: 5)
        do {
            _ = try await p.run(sleep: noWait) { _ -> Int in
                await counter.bump()
                throw MangaError.http(status: 502, body: "")
            }
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? MangaError, .http(status: 502, body: ""))
        }
        let count = await counter.value
        XCTAssertEqual(count, 2)
    }

    func testDoesNotRetryPermanentFailures() async {
        let counter = AttemptCounter()
        do {
            _ = try await RetryPolicy(maxAttempts: 5).run(sleep: noWait) { _ -> Int in
                await counter.bump()
                throw MangaError.unauthorized
            }
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? MangaError, .unauthorized)
        }
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testSlowAttemptTimesOutThenRetries() async throws {
        let counter = AttemptCounter()
        let p = RetryPolicy(maxAttempts: 2, attemptTimeout: 0.1)
        let start = Date()
        let value = try await p.run(sleep: noWait) { attempt -> String in
            await counter.bump()
            if attempt == 1 { try await Task.sleep(nanoseconds: 30_000_000_000) }
            return "ok"
        }
        XCTAssertEqual(value, "ok")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        let count = await counter.value
        XCTAssertEqual(count, 2)
    }

    func testTimeoutErrorWhenEveryAttemptHangs() async {
        let p = RetryPolicy(maxAttempts: 2, attemptTimeout: 0.05)
        do {
            _ = try await p.run(sleep: noWait) { _ -> Int in
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return 1
            }
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    func testWaitsBetweenAttempts() async throws {
        let waits = DelayRecorder()
        let p = RetryPolicy(maxAttempts: 3, attemptTimeout: 5, initialDelay: 0.5, multiplier: 2, maxDelay: 5)
        _ = try? await p.run(sleep: { await waits.add($0) }) { _ -> Int in throw URLError(.timedOut) }
        let recorded = await waits.values
        XCTAssertEqual(recorded, [0.5, 1.0])
    }

    func testCancellationStopsRetrying() async {
        let counter = AttemptCounter()
        let task = Task {
            try await RetryPolicy(maxAttempts: 100, attemptTimeout: 5, initialDelay: 0.05)
                .run { _ -> Int in
                    await counter.bump()
                    throw URLError(.timedOut)
                }
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError) }
        let count = await counter.value
        XCTAssertLessThan(count, 100)
    }

    func testFailureMessages() {
        XCTAssertEqual(PageLoadFailure.message(for: URLError(.timedOut)), "The server took too long to answer.")
        XCTAssertEqual(PageLoadFailure.message(for: URLError(.cannotConnectToHost)), "Couldn't reach the server.")
        XCTAssertEqual(PageLoadFailure.message(for: MangaError.http(status: 500, body: "")),
                       "The server returned an error (HTTP 500).")
        XCTAssertEqual(PageLoadFailure.message(for: MangaError.notFound), "The server doesn't have this page.")
    }
}

final class ImagePipelineRetryTests: XCTestCase {
    private let png = makePNG(width: 40, height: 60)
    private let noWait: @Sendable (TimeInterval) async throws -> Void = { _ in }

    func testRecoversFromServerErrors() async throws {
        let transport = ScriptedImageTransport(png: makePNG(width: 40, height: 60))
        transport.script("http://stub/p1", [.status(503), .status(500), .ok])
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil,
                                     retryPolicy: RetryPolicy(maxAttempts: 3, attemptTimeout: 5), sleep: noWait)
        let image = try await pipeline.load(URL(string: "http://stub/p1")!, server: ImageStubServer(), targetSize: nil)
        XCTAssertEqual(image.pixelSize, PageSize(width: 40, height: 60))
        XCTAssertEqual(transport.count("http://stub/p1"), 3)
    }

    func testHangingDownloadTimesOutAndRetries() async throws {
        let transport = ScriptedImageTransport(png: png)
        transport.script("http://stub/p2", [.hang, .ok])
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil,
                                     retryPolicy: RetryPolicy(maxAttempts: 2, attemptTimeout: 0.2), sleep: noWait)
        let image = try await pipeline.load(URL(string: "http://stub/p2")!, server: ImageStubServer(), targetSize: nil)
        XCTAssertEqual(image.pixelSize.width, 40)
        XCTAssertEqual(transport.count("http://stub/p2"), 2)
    }

    func testGivesUpAndALaterLoadTriesAgain() async throws {
        let transport = ScriptedImageTransport(png: png)
        transport.script("http://stub/p3", [.status(500), .status(500), .ok])
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil,
                                     retryPolicy: RetryPolicy(maxAttempts: 2, attemptTimeout: 5), sleep: noWait)
        let url = URL(string: "http://stub/p3")!
        do {
            _ = try await pipeline.load(url, server: ImageStubServer(), targetSize: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? MangaError, .http(status: 500, body: ""))
        }
        // The user presses Retry: nothing about the failure was cached.
        let image = try await pipeline.load(url, server: ImageStubServer(), targetSize: nil)
        XCTAssertEqual(image.pixelSize.height, 60)
        XCTAssertEqual(transport.count("http://stub/p3"), 3)
    }

    func testPermanentFailureIsNotRetried() async {
        let transport = ScriptedImageTransport(png: png)
        transport.script("http://stub/p4", [.status(404), .ok])
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil,
                                     retryPolicy: RetryPolicy(maxAttempts: 3, attemptTimeout: 5), sleep: noWait)
        do {
            _ = try await pipeline.load(URL(string: "http://stub/p4")!, server: ImageStubServer(), targetSize: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? MangaError, .notFound)
        }
        XCTAssertEqual(transport.count("http://stub/p4"), 1)
    }

    func testQueueingForASlotDoesNotCountAsTimeout() async throws {
        // One slot and three downloads of 1 s each: the last one waits
        // about 2 s for its turn, longer than the 1.5 s limit, and must
        // still succeed because only its own download is timed. (With
        // 0.2 s / 0.3 s a busy CI runner overran the limit on its own.)
        let transport = ScriptedImageTransport(png: png)
        for name in ["a", "b", "c"] { transport.script("http://stub/q\(name)", [.delay(1.0)]) }
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil, maxConcurrentDownloads: 1,
                                     retryPolicy: RetryPolicy(maxAttempts: 1, attemptTimeout: 1.5), sleep: noWait)
        let server = ImageStubServer()
        async let a = pipeline.load(URL(string: "http://stub/qa")!, server: server, targetSize: nil)
        async let b = pipeline.load(URL(string: "http://stub/qb")!, server: server, targetSize: nil)
        async let c = pipeline.load(URL(string: "http://stub/qc")!, server: server, targetSize: nil)
        let images = try await [a, b, c]
        XCTAssertEqual(images.map(\.pixelSize.width), [40, 40, 40])
    }

    func testPrefetchRetriesToo() async throws {
        let transport = ScriptedImageTransport(png: png)
        transport.script("http://stub/p5", [.status(502), .ok])
        let pipeline = ImagePipeline(transport: transport, diskDirectory: nil,
                                     retryPolicy: RetryPolicy(maxAttempts: 2, attemptTimeout: 5), sleep: noWait)
        let got = expectation(description: "size")
        pipeline.prefetch([URL(string: "http://stub/p5")!], server: ImageStubServer(), targetSize: nil) { _, size in
            XCTAssertEqual(size.width, 40)
            got.fulfill()
        }
        await fulfillment(of: [got], timeout: 5)
    }
}

// MARK: Helpers

actor AttemptCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}

actor DelayRecorder {
    private(set) var values: [TimeInterval] = []
    func add(_ v: TimeInterval) { values.append(v) }
}

/// Answers each URL from a script, one step per request; the last step
/// repeats. Unknown URLs are 404.
final class ScriptedImageTransport: HTTPTransport, @unchecked Sendable {
    enum Step { case ok, status(Int), hang, delay(TimeInterval) }

    private let lock = NSLock()
    private let png: Data
    private var scripts: [String: [Step]] = [:]
    private var counts: [String: Int] = [:]

    init(png: Data) { self.png = png }

    func script(_ url: String, _ steps: [Step]) {
        lock.lock(); scripts[url] = steps; lock.unlock()
    }

    func count(_ url: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[url] ?? 0
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!.absoluteString
        lock.lock()
        let n = counts[url] ?? 0
        counts[url] = n + 1
        let steps = scripts[url] ?? [.status(404)]
        lock.unlock()
        let step = steps[min(n, steps.count - 1)]
        func reply(_ status: Int, _ data: Data) -> (Data, HTTPURLResponse) {
            (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        switch step {
        case .ok:
            return reply(200, png)
        case .status(let code):
            return reply(code, Data())
        case .hang:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return reply(200, png)
        case .delay(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return reply(200, png)
        }
    }
}
