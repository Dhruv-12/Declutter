import XCTest

/// Select, select all, review, cancel (nothing deleted), confirm delete and the space-freed summary,
/// for every category. Needs the "standard" seeded library (phase "ui").
final class CategoryFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try Phase.require("ui")
        app = .launchDeclutter()
    }

    func testScreenshots() {
        app.openCategory("screenshots")
        waitForLabel(app.screenSummary, startsWith: "5 screenshots")
        let thumbnails = app.all("thumbnail")
        XCTAssertEqual(thumbnails.count, 5)

        // Select and deselect one.
        thumbnails.element(boundBy: 0).tap()
        waitForLabel(app.reviewBar, startsWith: "Review 1 screenshot ·")
        thumbnails.element(boundBy: 0).tap()
        waitForLabel(app.reviewBar, startsWith: "Select screenshots to review")
        XCTAssertFalse(app.reviewBar.isEnabled)

        // Select all, review, cancel: nothing is deleted.
        app.button(startingWith: "Select all 5").tap()
        waitForLabel(app.reviewBar, startsWith: "Review 5 screenshots")
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 5 items")
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.buttons["review.delete"].waitForNonExistence(timeout: 5))
        waitForLabel(app.screenSummary, startsWith: "5 screenshots")

        // "Review and delete all" also stops at the review screen.
        app.button(startingWith: "Review and delete all 5").tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 5 items")
        app.buttons["review.cancel"].tap()
        waitForLabel(app.screenSummary, startsWith: "5 screenshots")

        // Delete two for real.
        app.button(startingWith: "Deselect all 5").tap()
        thumbnails.element(boundBy: 0).tap()
        thumbnails.element(boundBy: 1).tap()
        waitForLabel(app.reviewBar, startsWith: "Review 2 screenshots")
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 2 items")
        app.buttons["review.delete"].tap()
        app.confirmSystemDelete()
        finishOnSummary(app, removed: "Photos removed")
        waitForLabel(app.category("screenshots"), contains: "3 screenshots")
    }

    func testLargeVideos() {
        app.openCategory("largeVideos")
        waitForLabel(app.screenSummary, startsWith: "3 videos")
        let rows = app.all("videoRow")
        XCTAssertEqual(rows.count, 3)

        rows.element(boundBy: 0).tap()
        waitForLabel(app.reviewBar, startsWith: "Review 1 video ·")
        app.button(startingWith: "Select all 3").tap()
        waitForLabel(app.reviewBar, startsWith: "Review 3 videos")
        app.button(startingWith: "Deselect all 3").tap()
        waitForLabel(app.reviewBar, startsWith: "Select videos to review")

        // The largest video is first; review it, cancel, then delete it.
        rows.element(boundBy: 0).tap()
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 1 item")
        app.buttons["review.cancel"].tap()
        waitForLabel(app.screenSummary, startsWith: "3 videos")

        app.reviewBar.tap()
        app.buttons["review.delete"].tap()
        app.confirmSystemDelete()
        finishOnSummary(app, removed: "Videos removed")
        waitForLabel(app.category("largeVideos"), contains: "2 videos")
    }

    func testSimilarPhotos() {
        app.openCategory("similarPhotos")
        // One burst of three near-identical shots and one pair saved twice: 2 sets, 3 extras.
        waitForLabel(app.screenSummary, startsWith: "2 sets · 3 extra photos", timeout: 240)
        XCTAssertEqual(app.all("thumbnail.best").count, 2, "Each set should mark one best photo")

        // Extras are pre-selected once the results are on screen; the best photos are not.
        waitForLabel(app.reviewBar, startsWith: "Review 3 photos")
        app.button(startingWith: "Deselect all duplicates").tap()
        waitForLabel(app.reviewBar, startsWith: "Select photos to review")
        app.button(startingWith: "Select all duplicates 3").tap()
        waitForLabel(app.reviewBar, startsWith: "Review 3 photos")

        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 3 items")
        app.buttons["review.cancel"].tap()
        waitForLabel(app.screenSummary, startsWith: "2 sets")

        app.reviewBar.tap()
        app.buttons["review.delete"].tap()
        app.confirmSystemDelete()
        finishOnSummary(app, removed: "Photos removed")
        waitForLabel(app.category("similarPhotos"), contains: "0 extra photos")
    }

    func testDuplicateContacts() {
        app.openCategory("duplicateContacts")
        waitForLabel(app.screenSummary, startsWith: "3 groups · 3 duplicates", timeout: 30)
        let rows = app.all("contactRow")

        // Select and deselect.
        rows.element(boundBy: 0).tap()
        waitForLabel(app.reviewBar, startsWith: "Review 1 contact")
        rows.element(boundBy: 0).tap()
        waitForLabel(app.reviewBar, startsWith: "Select contacts to review")

        // Review, cancel: nothing is deleted.
        rows.element(boundBy: 0).tap()
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 1 item")
        app.buttons["review.cancel"].tap()
        waitForLabel(app.screenSummary, startsWith: "3 groups")
        rows.element(boundBy: 0).tap()

        // Merge one group through its preview.
        app.buttons.matching(identifier: "contactGroup.merge").firstMatch.tap()
        let confirm = app.buttons["merge.confirm"]
        expectExists(confirm)
        confirm.tap()
        app.tapDialogButton("Merge contacts")
        waitForLabel(app.screenSummary, startsWith: "2 groups · 2 duplicates", timeout: 20)

        // Merge all, skipping the first group.
        app.button(startingWith: "Review and merge all 2").tap()
        let mergeAll = app.buttons["mergeAll.confirm"]
        waitForLabel(mergeAll, startsWith: "Merge 2 groups")
        app.buttons.matching(identifier: "mergeAll.toggle").firstMatch.tap()
        waitForLabel(mergeAll, startsWith: "Merge 1 group")
        mergeAll.tap()
        app.tapDialogButton("Merge 1 group")
        waitForLabel(app.screenSummary, startsWith: "1 group · 1 duplicate", timeout: 20)

        // Delete one contact from the skipped group.
        rows.element(boundBy: 0).tap()
        app.reviewBar.tap()
        waitForLabel(app.buttons["review.delete"], startsWith: "Delete 1 item")
        app.buttons["review.delete"].tap()
        app.tapDialogButton("Delete 1 item")
        finishOnSummary(app, removed: "Contacts removed")
        waitForLabel(app.category("duplicateContacts"), contains: "0 duplicates", timeout: 20)
    }
}
