import XCTest

/// Calendar cleanup, in Scripts/run-tests.sh's calendar phases.
final class CalendarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Phase "calendar": full access, three old one-off events seeded (plus a repeating and a recent one).
    func testCleanup() throws {
        try Phase.require("calendar")
        let app = XCUIApplication.launchDeclutter()
        app.openTool("calendar")
        waitForLabel(app.screenSummary, startsWith: "3 events older than 1 year", timeout: 20)
        let rows = app.all("eventRow")
        XCTAssertEqual(rows.count, 3, "Repeating and recent events aren't listed")

        // Select one, select all.
        rows.element(boundBy: 0).tap()
        waitForLabel(app.reviewBar, startsWith: "Review 1 event")
        app.button(startingWith: "Select all 3").tap()
        waitForLabel(app.reviewBar, startsWith: "Review 3 events")

        // Review, cancel: nothing deleted.
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 3 items")
        app.buttons["review.cancel"].tap()
        waitForLabel(app.screenSummary, startsWith: "3 events")

        // Delete one, through the extra warning.
        app.button(startingWith: "Deselect all 3").tap()
        rows.element(boundBy: 0).tap()
        app.reviewBar.tap()
        app.buttons["review.delete"].tap()
        app.tapDialogButton("Delete 1 item")
        finishOnSummary(app, removed: "Calendar events removed")
        waitForLabel(app.anyElement("tool.calendar"), contains: "2 old events", timeout: 20)
    }

    /// Phase "calendar-denied": access revoked.
    func testDeniedAccessExplainsWhatToDo() throws {
        try Phase.require("calendar-denied")
        let app = XCUIApplication.launchDeclutter()
        app.openTool("calendar")
        expectExists(app.staticTexts["Calendar access is off"], timeout: 10)
        expectExists(app.buttons["Open Settings"])
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Phase "calendar-ask": nothing decided yet. The reason is shown before iOS asks.
    func testAsksWithAReasonFirst() throws {
        try Phase.require("calendar-ask")
        let app = XCUIApplication.launchDeclutter()
        app.openTool("calendar")
        expectExists(app.staticTexts["Allow calendar access"], timeout: 10)
        app.buttons["Allow calendar access"].tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Full Access", "Allow", "OK"])).firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "iOS should ask for calendar access")
        allow.tap()
        expectExists(app.staticTexts["No old events"], timeout: 20)
    }
}
