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
        app.openTool("blurry")
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

    /// The standard library has three large videos.
    func testCompressVideos() {
        app.openTool("compress")
        let rows = app.all("compressRow")
        expectExists(rows.firstMatch, timeout: 20)
        XCTAssertEqual(rows.count, 3)

        // Compress the largest video to the smallest quality.
        rows.element(boundBy: 0).tap()
        let small = app.buttons["quality.small"]
        expectExists(small, timeout: 60, "Quality options didn't load")
        small.tap()
        app.buttons["compress.start"].tap()
        expectExists(app.staticTexts["compress.done"], timeout: 180, "Compression didn't finish")
        waitForLabel(app.staticTexts["compress.done"], startsWith: "Saved a")

        // Review the original, cancel: nothing deleted.
        app.buttons["compress.reviewOriginal"].tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 1 item")
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.buttons["review.delete"].waitForNonExistence(timeout: 5))

        // Keep both: the list now shows the copy too.
        app.buttons["compress.keepBoth"].tap()
        expectExists(app.staticTexts["Compressed copy"], timeout: 20)
        XCTAssertEqual(rows.count, 4)

        // Compress another and delete its original this time.
        rows.element(boundBy: 1).tap()
        expectExists(app.buttons["quality.small"], timeout: 60)
        app.buttons["quality.small"].tap()
        app.buttons["compress.start"].tap()
        expectExists(app.staticTexts["compress.done"], timeout: 180)
        app.buttons["compress.reviewOriginal"].tap()
        app.buttons["review.delete"].tap()
        app.confirmSystemDelete()
        finishOnSummary(app, removed: "Videos removed")
        waitForLabel(app.anyElement("tool.compress"), contains: "Saved", timeout: 20)
    }

    /// The widget itself lives on the Home Screen, which UI tests can't drive; this checks the guide.
    func testWidgetGuide() {
        app.openTool("widget")
        expectExists(app.anyElement("widget.steps"), timeout: 10)
        expectExists(app.descendants(matching: .any)["Preview of the small widget"])
        expectExists(app.descendants(matching: .any)["Preview of the medium widget"])
        expectExists(app.text(containing: "free of"), timeout: 10, "Previews should show real storage")
    }

    func testSwipeToSort() {
        app.openTool("swipe")

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
