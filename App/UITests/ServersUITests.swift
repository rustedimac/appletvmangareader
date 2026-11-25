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
        XCTAssertTrue(app.element("serverEditor.apiKey").exists)
        // Nothing typed yet, so it can't be saved or tested.
        XCTAssertFalse(app.element("serverEditor.save").isEnabled)
        XCTAssertFalse(app.element("serverEditor.test").isEnabled)
    }

    /// A pasted full OPDS URL stays as typed in the field (it used to be cut
    /// to the host on every change) and is enough to test and save.
    func testPastedOPDSURLIsKeptAndAccepted() {
        let opds = "http://kavita.test:5000/api/opds/fake-key-0000"
        let app = XCUIApplication.launched(tab: "settings", extra: ["-serverEditorPrefill", "kavita|\(opds)"])
        XCTAssertTrue(app.element("settings.addServer").waitForExistence(timeout: 10))
        select(app.element("settings.addServer"))
        let address = app.element("serverEditor.address")
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertEqual(address.value as? String, opds)
        XCTAssertTrue(app.element("serverEditor.save").isEnabled)
        XCTAssertTrue(app.element("serverEditor.test").isEnabled)
        let help = app.element("serverEditor.addressHelp")
        XCTAssertTrue(help.exists)
        XCTAssertTrue(help.label.contains("for example http://kavita.local:5000"), help.label)
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
