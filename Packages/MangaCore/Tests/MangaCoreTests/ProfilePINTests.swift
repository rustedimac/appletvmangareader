import XCTest
@testable import MangaCore

final class ProfilePINTests: XCTestCase {
    func testValidation() {
        XCTAssertTrue(ProfilePIN.isValid("0000"))
        XCTAssertTrue(ProfilePIN.isValid("1234"))
        XCTAssertFalse(ProfilePIN.isValid("123"))
        XCTAssertFalse(ProfilePIN.isValid("12345"))
        XCTAssertFalse(ProfilePIN.isValid("12a4"))
        XCTAssertFalse(ProfilePIN.isValid("١٢٣٤"), "non-ASCII digits are rejected")
        XCTAssertNil(ProfilePIN.makeRecord("12"))
    }

    func testHashVerifiesAndNeverStoresThePIN() throws {
        let record = try XCTUnwrap(ProfilePIN.makeRecord("4821", iterations: 1000))
        XCTAssertTrue(ProfilePIN.verify("4821", against: record))
        XCTAssertFalse(ProfilePIN.verify("4822", against: record))
        XCTAssertFalse(ProfilePIN.verify("482", against: record))
        XCTAssertEqual(record.hash.count, 32)
        XCTAssertEqual(record.salt.count, 16)
        let json = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertFalse(json.contains("4821"))
    }

    func testSaltsDiffer() throws {
        let a = try XCTUnwrap(ProfilePIN.makeRecord("1111", iterations: 1000))
        let b = try XCTUnwrap(ProfilePIN.makeRecord("1111", iterations: 1000))
        XCTAssertNotEqual(a.salt, b.salt)
        XCTAssertNotEqual(a.hash, b.hash)
    }

    func testKnownVector() throws {
        // Published PBKDF2-HMAC-SHA256 test vector: "password", "salt", 1 iteration.
        let derived = try XCTUnwrap(ProfilePIN.derive("password", salt: Data("salt".utf8), iterations: 1))
        XCTAssertEqual(derived.map { String(format: "%02x", $0) }.joined(),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    func testDefaultIterationsVerify() throws {
        let record = try XCTUnwrap(ProfilePIN.makeRecord("9090"))
        XCTAssertEqual(record.iterations, ProfilePIN.defaultIterations)
        XCTAssertTrue(ProfilePIN.verify("9090", against: record))
    }

    func testStore() {
        let store = InMemoryPINStore()
        let p = UUID()
        XCTAssertFalse(store.hasPIN(profile: p))
        XCTAssertFalse(store.verify("1111", profile: p))
        XCTAssertFalse(store.setPIN("abc", profile: p, iterations: 10))
        XCTAssertTrue(store.setPIN("1111", profile: p, iterations: 10))
        XCTAssertTrue(store.hasPIN(profile: p))
        XCTAssertTrue(store.verify("1111", profile: p))
        XCTAssertFalse(store.verify("2222", profile: p))
        store.setPIN(nil, profile: p)
        XCTAssertFalse(store.hasPIN(profile: p))
    }

    func testLimiterLocksOutAndBacksOff() {
        var limiter = PINAttemptLimiter()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for _ in 0..<4 { limiter.recordFailure(now: t0) }
        XCTAssertNil(limiter.lockoutRemaining(now: t0))
        limiter.recordFailure(now: t0)
        XCTAssertEqual(limiter.lockoutRemaining(now: t0), 30)
        XCTAssertNil(limiter.lockoutRemaining(now: t0.addingTimeInterval(31)))
        limiter.recordFailure(now: t0)
        XCTAssertEqual(limiter.lockoutRemaining(now: t0), 60)
        for _ in 0..<20 { limiter.recordFailure(now: t0) }
        XCTAssertEqual(limiter.lockoutRemaining(now: t0), PINAttemptLimiter.maxLockout)
        limiter.recordSuccess()
        XCTAssertNil(limiter.lockoutRemaining(now: t0))
        XCTAssertEqual(limiter.failures, 0)
    }

    func testEntry() {
        var e = PINEntry()
        e.append(1); e.append(2); e.deleteLast(); e.append(3)
        XCTAssertEqual(e.digits, "13")
        e.append(10)
        XCTAssertEqual(e.digits, "13")
        e.append(4); e.append(5); e.append(6)
        XCTAssertEqual(e.digits, "1345")
        XCTAssertTrue(e.isComplete)
        e.clear()
        XCTAssertEqual(e.digits, "")
        e.deleteLast()
        XCTAssertEqual(e.digits, "")
    }

    func testLocks() {
        let store = InMemoryPINStore()
        let me = UUID(), kid = UUID(), open = UUID()
        store.setPIN("1111", profile: me, iterations: 10)
        store.setPIN("3333", profile: kid, iterations: 10)
        var locks = ProfileLocks()
        let t0 = Date(timeIntervalSince1970: 0)

        XCTAssertTrue(locks.isUnlocked(open, store: store), "no PIN, nothing to unlock")
        XCTAssertFalse(locks.isUnlocked(me, store: store))
        XCTAssertEqual(locks.attempt("3333", candidates: [me], store: store, now: t0), .wrong(triesLeft: 4))
        XCTAssertEqual(locks.attempt("1111", candidates: [me], store: store, now: t0), .unlocked(me))
        XCTAssertTrue(locks.isUnlocked(me, store: store))
        XCTAssertFalse(locks.isUnlocked(kid, store: store))

        // Any of several profiles.
        XCTAssertEqual(locks.attempt("3333", candidates: [me, kid], store: store, now: t0), .unlocked(kid))

        locks.lockAll()
        XCTAssertFalse(locks.isUnlocked(me, store: store))

        for _ in 0..<4 { _ = locks.attempt("0000", candidates: [me], store: store, now: t0) }
        XCTAssertEqual(locks.attempt("0000", candidates: [me], store: store, now: t0), .lockedOut(seconds: 30))
        XCTAssertEqual(locks.attempt("1111", candidates: [me], store: store, now: t0.addingTimeInterval(10)),
                       .lockedOut(seconds: 20), "even the right PIN waits out a lockout")
        XCTAssertEqual(locks.attempt("1111", candidates: [me], store: store, now: t0.addingTimeInterval(31)), .unlocked(me))
    }
}
