import XCTest
@testable import MangaCore

/// A typed Kavita API key must survive Save (John, 2026-11-25: Test
/// Connection passed, Save closed the form, Settings still said the server
/// had no login). Saving now reads the login back and reports a failure.
final class CredentialSaveTests: XCTestCase {
    /// Accepts writes and keeps nothing, like a Keychain refusing access.
    final class DroppingStore: SecretStore, KeychainStatusReporting, @unchecked Sendable {
        var lastStatus: Int32? = -34018
        func credential(profile: UUID, server: UUID) -> ServerCredential? { nil }
        func setCredential(_ credential: ServerCredential?, profile: UUID, server: UUID) {}
    }

    func testSaveReadsTheLoginBack() throws {
        let store = InMemorySecretStore()
        let profile = UUID(), server = UUID()
        let login = ServerCredential(apiKey: "typed-key", username: "john")
        try store.saveCredential(login, profile: profile, server: server)
        XCTAssertEqual(store.credential(profile: profile, server: server), login)
    }

    func testDroppedWriteIsReportedWithTheKeychainStatus() {
        let store = DroppingStore()
        XCTAssertThrowsError(try store.saveCredential(ServerCredential(apiKey: "k"), profile: UUID(), server: UUID())) {
            let error = $0 as? CredentialSaveError
            XCTAssertEqual(error?.status, -34018)
            XCTAssertTrue(error?.errorDescription?.contains("couldn't be saved") == true)
        }
    }

    func testClearingALoginNeverThrows() {
        XCTAssertNoThrow(try DroppingStore().saveCredential(nil, profile: UUID(), server: UUID()))
    }

    func testSharedFallbackStoreReportsTheLocalStatus() {
        let store = SharedFallbackSecretStore(local: DroppingStore(), shared: InMemorySharedServerStore())
        XCTAssertThrowsError(try store.saveCredential(ServerCredential(apiKey: "k"), profile: UUID(), server: UUID())) {
            XCTAssertEqual(($0 as? CredentialSaveError)?.status, -34018)
        }
    }

    func testFileStoreRoundTripsAndRemovesItsFileWhenEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("credentials.json")
        let store = FileSecretStore(url: url)
        let profile = UUID(), server = UUID()
        let login = ServerCredential(apiKey: "typed-key")
        try store.saveCredential(login, profile: profile, server: server)
        XCTAssertEqual(FileSecretStore(url: url).credential(profile: profile, server: server), login,
                       "a new store (next launch) reads it back")
        store.setCredential(nil, profile: profile, server: server)
        XCTAssertNil(store.credential(profile: profile, server: server))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    #if canImport(Security)
    func testOnlyMissingKeychainAccessFallsBackToTheFile() {
        XCTAssertTrue(KeychainSecretStore.usesFallback(errSecMissingEntitlement))
        XCTAssertTrue(KeychainSecretStore.usesFallback(errSecNotAvailable))
        XCTAssertFalse(KeychainSecretStore.usesFallback(errSecDuplicateItem))
        XCTAssertFalse(KeychainSecretStore.usesFallback(errSecSuccess))
    }
    #endif

    /// John's exact steps: editing a Kavita server that has no login yet
    /// (so the form opens on username and password), switching to API Key
    /// and typing one gives a login to save.
    func testTypedKavitaKeyOnAServerWithoutLoginIsSaved() {
        let config = ServerConfig(kind: .kavita, name: "kavita-en.home", baseURL: URL(string: "http://kavita-en.home")!)
        var d = ServerDraft(editing: config, credential: nil, syncProgress: false)
        XCTAssertEqual(d.kavitaMethod, .password)
        d.kavitaMethod = .apiKey
        d.apiKey = " typed-key "
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.credential?.apiKey, "typed-key")
    }
}
