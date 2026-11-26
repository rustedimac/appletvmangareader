import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How a network request is retried: a time limit per attempt, a number of
/// attempts, and a growing pause between them. Only failures that can pass
/// on their own are retried (timeouts, dropped connections, HTTP 5xx, 408,
/// 429); a wrong login, a missing page or a cancelled task fails at once.
public struct RetryPolicy: Sendable, Hashable {
    /// Total tries, including the first. At least 1.
    public var maxAttempts: Int
    /// Seconds one attempt may take before it is abandoned as
    /// `URLError(.timedOut)`. 0 or infinity means no limit.
    public var attemptTimeout: TimeInterval
    /// Pause before the first retry, in seconds.
    public var initialDelay: TimeInterval
    /// Each later pause is the previous one times this.
    public var multiplier: Double
    /// Longest pause, in seconds.
    public var maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, attemptTimeout: TimeInterval = 20, initialDelay: TimeInterval = 0.75,
                multiplier: Double = 2, maxDelay: TimeInterval = 5) {
        self.maxAttempts = max(1, maxAttempts)
        self.attemptTimeout = attemptTimeout
        self.initialDelay = max(0, initialDelay)
        self.multiplier = max(1, multiplier)
        self.maxDelay = max(0, maxDelay)
    }

    /// Covers and pages: three tries of 20 seconds, 0.75 s then 1.5 s apart,
    /// so a page gives up in about a minute at worst and usually recovers
    /// from a blip in under two seconds.
    public static let images = RetryPolicy()

    /// Chapter page lists: same shape, a little more patient per attempt
    /// because Suwayomi may have to fetch the chapter from its source.
    public static let pageLists = RetryPolicy(maxAttempts: 3, attemptTimeout: 45, initialDelay: 1, maxDelay: 5)

    /// One try, no time limit beyond the request's own.
    public static let once = RetryPolicy(maxAttempts: 1, attemptTimeout: 0)

    /// The pause before retry number `retry` (1 = the first retry).
    public func delay(beforeRetry retry: Int) -> TimeInterval {
        min(maxDelay, initialDelay * pow(multiplier, Double(max(0, retry - 1))))
    }

    /// Runs `operation` until it succeeds, a failure isn't worth retrying,
    /// or the attempts run out; the last error is thrown. Each attempt gets
    /// `attemptTimeout` unless `timingEachAttempt` is false (callers that
    /// queue first, like the image pipeline, start the clock themselves).
    /// `operation` receives the attempt number (1-based). Cancelling the
    /// calling task stops at once with `CancellationError`.
    public func run<T: Sendable>(
        timingEachAttempt: Bool = true,
        sleep: @Sendable (TimeInterval) async throws -> Void = RetryPolicy.taskSleep,
        _ operation: @escaping @Sendable (_ attempt: Int) async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                let current = attempt
                return try await Self.withTimeout(timingEachAttempt ? attemptTimeout : 0) { try await operation(current) }
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                guard attempt < maxAttempts, Self.isRetryable(error) else { throw error }
                try await sleep(delay(beforeRetry: attempt))
                attempt += 1
            }
        }
    }

    /// `Task.sleep` in seconds.
    public static let taskSleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Runs `operation`, throwing `URLError(.timedOut)` if it takes longer
    /// than `seconds` (the operation is cancelled).
    public static func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                                _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        guard seconds > 0, seconds.isFinite else { return try await operation() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    /// Whether `error` may go away by trying again.
    public static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .badServerResponse, .resourceUnavailable,
                 .cannotLoadFromNetwork, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
                 .secureConnectionFailed, .zeroByteResource:
                return true
            default:
                return false
            }
        }
        if let manga = error as? MangaError {
            switch manga {
            case .http(let status, _):
                return status == 408 || status == 425 || status == 429 || (500...599).contains(status)
            case .unreachable:
                return true
            default:
                return false
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return isRetryable(URLError(URLError.Code(rawValue: ns.code)))
        }
        return false
    }
}

/// A short, human-readable reason a page didn't load, for the reader's
/// "didn't load" placeholder.
public enum PageLoadFailure {
    public static func message(for error: Error) -> String {
        if let url = (error as? URLError) ?? (error as NSError).asURLError {
            switch url.code {
            case .timedOut: return "The server took too long to answer."
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "The network connection was lost."
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach the server."
            default: return "The download failed."
            }
        }
        switch error as? MangaError {
        case .unauthorized?: return "The server refused the login."
        case .notFound?: return "The server doesn't have this page."
        case .unreachable?: return "Couldn't reach the server."
        case .http(let status, _)?: return "The server returned an error (HTTP \(status))."
        default: break
        }
        if error as? ImagePipelineError == .undecodable { return "The page isn't an image the TV can show." }
        return "The page couldn't be loaded."
    }
}

private extension NSError {
    var asURLError: URLError? {
        domain == NSURLErrorDomain ? URLError(URLError.Code(rawValue: code)) : nil
    }
}
