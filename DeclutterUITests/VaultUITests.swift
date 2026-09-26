import XCTest

/// The private vault's PIN flow. The simulator has no Face ID, so the vault goes straight to the PIN.
final class VaultUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try Phase.require("ui")
        app = .launchDeclutter()
    }

    private func type(_ pin: String) {
        for digit in pin { app.buttons["pin.\(digit)"].tap() }
    }

    func testCreatePINLockAndUnlock() {
        app.openTool("vault")

        // Create a PIN, twice.
        expectExists(app.staticTexts["Create a PIN"], timeout: 10)
        XCTAssertFalse(app.buttons["pin.submit"].isEnabled, "Needs at least 4 digits")
        type("2468")
        app.buttons["pin.submit"].tap()
        expectExists(app.staticTexts["Enter it again"])
        type("2468")
        app.buttons["pin.submit"].tap()
        expectExists(app.staticTexts["Your vault is empty"], timeout: 10)

        // Lock, then a wrong PIN is refused and the right one opens it.
        app.buttons["vault.lock"].tap()
        expectExists(app.staticTexts["Your vault is locked"])
        type("1111")
        app.buttons["pin.submit"].tap()
        expectExists(app.anyElement("vault.wrongPIN"))
        type("2468")
        app.buttons["pin.submit"].tap()
        expectExists(app.staticTexts["Your vault is empty"], timeout: 10)

        // Leaving the app locks the vault.
        XCUIDevice.shared.press(.home)
        app.activate()
        expectExists(app.staticTexts["Your vault is locked"], timeout: 10)
    }
}
