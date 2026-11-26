import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(Security)
import Security
#endif

/// A salted PBKDF2-SHA256 hash of a profile's PIN. The PIN itself is never
/// stored. Kept in the Keychain (`KeychainPINStore`), never in `AppState`.
public struct PINRecord: Codable, Hashable, Sendable {
    public var salt: Data
    public var hash: Data
    public var iterations: Int

    public init(salt: Data, hash: Data, iterations: Int) {
        self.salt = salt
        self.hash = hash
        self.iterations = iterations
    }
}

public enum ProfilePIN {
    public static let length = 4
    /// About 40 ms on an Apple TV. A 4-digit PIN can't resist an offline
    /// search however slow the hash, so the real protection is the
    /// Keychain plus the attempt limit; the hash keeps the PIN out of
    /// backups and logs.
    public static let defaultIterations = 100_000

    /// Exactly four ASCII digits.
    public static func isValid(_ pin: String) -> Bool {
        pin.count == length && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    public static func makeRecord(_ pin: String, iterations: Int = defaultIterations,
                                  salt: Data? = nil) -> PINRecord? {
        guard isValid(pin) else { return nil }
        let salt = salt ?? randomSalt()
        guard let hash = derive(pin, salt: salt, iterations: iterations) else { return nil }
        return PINRecord(salt: salt, hash: hash, iterations: iterations)
    }

    public static func verify(_ pin: String, against record: PINRecord) -> Bool {
        guard isValid(pin), let hash = derive(pin, salt: record.salt, iterations: record.iterations),
              hash.count == record.hash.count else { return false }
        // Constant-time comparison.
        var diff: UInt8 = 0
        for (a, b) in zip(hash, record.hash) { diff |= a ^ b }
        return diff == 0
    }

    static func randomSalt() -> Data {
        var rng = SystemRandomNumberGenerator()
        return Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &rng) })
    }

    static func derive(_ pin: String, salt: Data, iterations: Int) -> Data? {
        #if canImport(CommonCrypto)
        guard iterations > 0 else { return nil }
        let password = Array(pin.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes -> Int32 in
            password.withUnsafeBufferPointer { pw -> Int32 in
                pw.baseAddress!.withMemoryRebound(to: Int8.self, capacity: password.count) { pwPtr in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwPtr, password.count,
                                         saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         &derived, derived.count)
                }
            }
        }
        return Int(status) == Int(kCCSuccess) ? Data(derived) : nil
        #else
        return nil
        #endif
    }
}

/// Wrong-PIN throttling: five free tries, then a lockout that starts at
/// 30 seconds and doubles with each further miss, up to 15 minutes.
public struct PINAttemptLimiter: Hashable, Sendable {
    public static let freeAttempts = 5
    public static let firstLockout: TimeInterval = 30
    public static let maxLockout: TimeInterval = 15 * 60

    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?

    public init() {}

    /// Seconds left before another try is allowed, or nil if allowed now.
    public func lockoutRemaining(now: Date = Date()) -> TimeInterval? {
        guard let lockedUntil, lockedUntil > now else { return nil }
        return lockedUntil.timeIntervalSince(now)
    }

    public mutating func recordFailure(now: Date = Date()) {
        failures += 1
        guard failures >= Self.freeAttempts else { return }
        let doublings = Double(failures - Self.freeAttempts)
        let delay = min(Self.firstLockout * pow(2, doublings), Self.maxLockout)
        lockedUntil = now.addingTimeInterval(delay)
    }

    public mutating func recordSuccess() {
        failures = 0
        lockedUntil = nil
    }
}

/// The four-digit entry field behind the on-screen keypad.
public struct PINEntry: Hashable, Sendable {
    public private(set) var digits = ""

    public init() {}

    public var isComplete: Bool { digits.count == ProfilePIN.length }

    public mutating func append(_ digit: Int) {
        guard (0...9).contains(digit), !isComplete else { return }
        digits.append(String(digit))
    }

    public mutating func deleteLast() {
        if !digits.isEmpty { digits.removeLast() }
    }

    public mutating func clear() { digits = "" }
}

/// Stores each profile's `PINRecord`.
public protocol PINStore: AnyObject, Sendable {
    func record(profile: UUID) -> PINRecord?
    func setRecord(_ record: PINRecord?, profile: UUID)
}

public extension PINStore {
    func hasPIN(profile: UUID) -> Bool { record(profile: profile) != nil }

    /// Sets or (with nil) removes a profile's PIN. Returns false for a PIN
    /// that isn't four digits.
    @discardableResult
    func setPIN(_ pin: String?, profile: UUID, iterations: Int = ProfilePIN.defaultIterations) -> Bool {
        guard let pin else {
            setRecord(nil, profile: profile)
            return true
        }
        guard let record = ProfilePIN.makeRecord(pin, iterations: iterations) else { return false }
        setRecord(record, profile: profile)
        return true
    }

    func verify(_ pin: String, profile: UUID) -> Bool {
        guard let record = record(profile: profile) else { return false }
        return ProfilePIN.verify(pin, against: record)
    }
}

public final class InMemoryPINStore: PINStore, @unchecked Sendable {
    private var values: [UUID: PINRecord] = [:]
    private let lock = NSLock()

    public init() {}

    public func record(profile: UUID) -> PINRecord? {
        lock.lock(); defer { lock.unlock() }
        return values[profile]
    }

    public func setRecord(_ record: PINRecord?, profile: UUID) {
        lock.lock(); defer { lock.unlock() }
        values[profile] = record
    }
}

#if canImport(Security)
/// PIN hashes in the Keychain, one generic password per profile. They stay
/// on this Apple TV (`ThisDeviceOnly`) and aren't synced.
public final class KeychainPINStore: PINStore, @unchecked Sendable {
    let service: String

    public init(service: String = "com.rustedimac.MangaReader.pins") {
        self.service = service
    }

    private func query(_ profile: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: profile.uuidString]
    }

    public func record(profile: UUID) -> PINRecord? {
        var q = query(profile)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PINRecord.self, from: data)
    }

    public func setRecord(_ record: PINRecord?, profile: UUID) {
        SecItemDelete(query(profile) as CFDictionary)
        guard let record, let data = try? JSONEncoder().encode(record) else { return }
        var q = query(profile)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}
#endif
