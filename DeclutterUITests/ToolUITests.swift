import XCTest

/// Bonus tools. Runs in the "ui" phase after the category flows (classes run alphabetically).
final class ToolUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try Phase.require("ui")
        app = .launchDeclutter()
    }

    /// The standard library has two out-of-focus photos; everything else is sharp.
    func testBlurryPhotos() {
        let tile = app.anyElement("tool.blurry")
        expectExists(tile, timeout: 20)
        tile.tap()
        waitForLabel(app.screenSummary, startsWith: "2 blurry photos", timeout: 120)
        XCTAssertEqual(app.all("thumbnail").count, 2)

        // Select one, select all, deselect all.
        app.all("thumbnail").element(boundBy: 0).tap()
        waitForLabel(app.reviewBar, startsWith: "Review 1 photo ·")
        app.button(startingWith: "Select all 2").tap()
        waitForLabel(app.reviewBar, startsWith: "Review 2 photos")

        // Review, cancel: nothing deleted.
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 2 items")
        app.buttons["review.cancel"].tap()
        waitForLabel(app.screenSummary, startsWith: "2 blurry photos")

        // Delete one for real.
        app.button(startingWith: "Deselect all 2").tap()
        app.all("thumbnail").element(boundBy: 0).tap()
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 1 item")
        app.buttons["review.delete"].tap()
        app.confirmSystemDelete()
        finishOnSummary(app, removed: "Photos removed")
        waitForLabel(app.anyElement("tool.blurry"), contains: "1 photo", timeout: 20)
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
