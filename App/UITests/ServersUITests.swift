import XCTest

final class ServersUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEmptySettingsOffersAddServer() {
        let app = XCUIApplication.launched(tab: "settings")
        XCTAssertTrue(app.element("settings.addServer").waitForExistence(timeout: 10))
        select(app.element("settings.addServer"))
        XCTAssertTrue(app.element("serverEditor.address").waitForExistence(timeout: 5))
        // Kavita signs in with a username and password by default.
        XCTAssertTrue(app.element("serverEditor.kavitaMethod").exists)
        XCTAssertTrue(app.element("serverEditor.username").exists)
        XCTAssertTrue(app.element("serverEditor.password").exists)
        // Nothing typed yet, so it can't be saved or tested.
        XCTAssertFalse(app.element("serverEditor.save").isEnabled)
        XCTAssertFalse(app.element("serverEditor.test").isEnabled)
    }

    func testEditAndRemoveSeededServer() {
        let app = XCUIApplication.launched(seed: "servers", tab: "settings")
        let kavita = app.element("settings.server.Test Kavita")
        XCTAssertTrue(kavita.waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("settings.server.Test Suwayomi").exists)

        select(app.element("settings.server.Test Suwayomi"))
        XCTAssertTrue(app.element("serverEditor.username").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("serverEditor.sync").exists)
        XCTAssertTrue(app.element("serverEditor.save").isEnabled)
        select(app.element("serverEditor.remove"))
        select(app.element("serverEditor.confirmRemove"), .right)

        XCTAssertTrue(app.element("settings.server.Test Kavita").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("settings.server.Test Suwayomi").exists)
    }

    func testReaderDefaultsOpens() {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.readerDefaults"))
        XCTAssertTrue(app.element("readerDefaults.mode").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("readerDefaults.reset").exists)
    }
}

/// Several addresses per server, and filling the server form from a phone.
final class ServerAddressesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEditorShowsEveryAddress() {
        let app = XCUIApplication.launched(seed: "multiAddress", tab: "settings")
        select(app.element("settings.server.Home Kavita"))
        let other = app.element("serverEditor.altAddress.0")
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        XCTAssertEqual(other.value as? String, "https://kavita-remote.test")
        XCTAssertEqual(app.element("serverEditor.address").value as? String, "http://kavita.test")
        XCTAssertTrue(app.element("serverEditor.addAddress").exists)
    }

    func testAddAnotherAddressAddsAField() {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.addServer"))
        XCTAssertTrue(app.element("serverEditor.address").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("serverEditor.altAddress.0").exists)
        select(app.element("serverEditor.addAddress"))
        XCTAssertTrue(app.element("serverEditor.altAddress.0").waitForExistence(timeout: 5))
    }

    /// Plays the phone: posts the setup form to the page the Apple TV
    /// serves, then checks the editor was filled in.
    func testPhoneSetupFillsTheForm() throws {
        let app = XCUIApplication.launched(tab: "settings")
        select(app.element("settings.addServer"))
        select(app.element("serverEditor.phoneSetup"), .up)

        let address = app.element("phoneSetup.address")
        let problem = app.element("phoneSetup.problem")
        let deadline = Date().addingTimeInterval(15)
        while !address.exists && !problem.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        if problem.exists { throw XCTSkip("No network in this simulator: \(problem.label)") }
        XCTAssertTrue(address.exists, "the setup page starts")
        XCTAssertTrue(app.element("phoneSetup.qr").exists)

        // The app listens on every interface, so loopback reaches it too.
        var page = try XCTUnwrap(URLComponents(string: address.label), address.label)
        page.host = "127.0.0.1"
        var request = URLRequest(url: try XCTUnwrap(page.url).appendingPathComponent("submit"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"kind":"suwayomi","name":"Phone Suwayomi","address":"http://suwayomi.phone.test:4567","alternateAddresses":["https://suwayomi-remote.phone.test"],"username":"","password":""}"#.utf8)
        let answered = expectation(description: "the Apple TV answers")
        let status = StatusBox()
        URLSession.shared.dataTask(with: request) { _, response, _ in
            status.code = (response as? HTTPURLResponse)?.statusCode ?? -1
            answered.fulfill()
        }.resume()
        wait(for: [answered], timeout: 15)
        XCTAssertEqual(status.code, 200)

        // The setup screen closes and the editor shows what the phone sent.
        let field = app.element("serverEditor.address")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let filled = NSPredicate(format: "value == %@", "http://suwayomi.phone.test:4567")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: filled, object: field)], timeout: 10), .completed,
                       "address field: \(String(describing: field.value))")
        XCTAssertEqual(app.element("serverEditor.altAddress.0").value as? String, "https://suwayomi-remote.phone.test")
        XCTAssertTrue(app.element("serverEditor.username").exists, "the type switched to Suwayomi")
    }
}

private final class StatusBox: @unchecked Sendable {
    var code = 0
}
