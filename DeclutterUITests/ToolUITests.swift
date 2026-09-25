import XCTest

/// Bonus tools. Runs in the "ui" phase after the category flows (classes run alphabetically).
final class ToolUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try Phase.require("ui")
        app = .launchDeclutter()
    }

    func testSwipeToSort() {
        let tile = app.anyElement("tool.swipe")
        expectExists(tile, timeout: 20)
        tile.tap()

        let card = app.anyElement("swipe.card")
        expectExists(card, timeout: 20)
        waitForLabel(app.reviewBar, startsWith: "Select photos to review")

        // Swipe left marks the photo; undo brings it back.
        card.swipeLeft(velocity: .fast)
        waitForLabel(app.reviewBar, startsWith: "Review 1 photo ·")
        app.buttons["swipe.undo"].tap()
        waitForLabel(app.reviewBar, startsWith: "Select photos to review")

        // Buttons work too: mark one, keep one, mark one.
        app.buttons["swipe.delete"].tap()
        app.buttons["swipe.keep"].tap()
        app.buttons["swipe.delete"].tap()
        waitForLabel(app.reviewBar, startsWith: "Review 2 photos")

        // Review, cancel: nothing deleted, both still marked.
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 2 items")
        app.buttons["review.cancel"].tap()
        waitForLabel(app.reviewBar, startsWith: "Review 2 photos")

        // Delete them for real.
        app.reviewBar.tap()
        app.buttons["review.delete"].tap()
        app.confirmSystemDelete()
        finishOnSummary(app, removed: "Photos removed")
        expectExists(app.anyElement("tool.swipe"), timeout: 10)
    }
}
