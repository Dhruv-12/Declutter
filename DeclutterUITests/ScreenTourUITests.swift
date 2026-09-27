import XCTest

/// Visits every main screen, saves a screenshot of each in the result bundle, and checks that each
/// screen's main button is on screen and can be tapped. Run it on different iPhones and text sizes:
///
///   PHASES=screens DEVICE="iPhone SE (3rd generation)" TEXT_SIZE=accessibility-extra-extra-extra-large Scripts/run-tests.sh
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        try Phase.require("screens")
    }

    func testEveryScreen() {
        app = .launchDeclutter()

        // Home.
        expectExists(app.category("screenshots"), timeout: 30)
        shot("01 Home")
        expectUsable(app.category("screenshots"), "Home category row")
        app.swipeUp()
        shot("02 Home, further down")
        app.swipeUp()
        shot("02b Home, tools")
        for _ in 0..<6 { app.swipeDown() }

        // Screenshots, then the review screen.
        app.openCategory("screenshots")
        expectExists(app.screenSummary, timeout: 20)
        app.button(startingWith: "Select all").tap()
        shot("03 Screenshots, all selected")
        expectUsable(app.reviewBar, "Review bar")
        app.reviewBar.tap()
        expectExists(app.buttons["review.delete"], timeout: 10)
        shot("04 Review")
        expectUsable(app.buttons["review.delete"], "Delete button")
        expectUsable(app.buttons["review.cancel"], "Cancel button")
        app.buttons["review.cancel"].tap()
        app.goBack()

        // Large videos.
        app.openCategory("largeVideos")
        expectExists(app.all("videoRow").firstMatch, timeout: 20)
        shot("05 Large videos")
        expectUsable(app.all("videoRow").firstMatch, "First video")
        app.goBack()

        // Similar photos (on the simulator this ends empty: Vision doesn't run there).
        app.openCategory("similarPhotos")
        sleep(3)
        shot("06 Similar photos")
        app.goBack()

        // Duplicate contacts and the merge editor.
        app.openCategory("duplicateContacts")
        expectExists(app.all("contactRow").firstMatch, timeout: 30)
        shot("07 Duplicate contacts")
        app.buttons.matching(identifier: "contactGroup.merge").firstMatch.tap()
        expectExists(app.buttons["merge.confirm"], timeout: 10)
        shot("08 Merge editor")
        expectUsable(app.buttons["merge.confirm"], "Merge button")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        app.goBack()

        // Tools.
        app.openTool("swipe")
        expectExists(app.anyElement("swipe.card"), timeout: 20)
        shot("09 Swipe to sort")
        expectUsable(app.buttons["swipe.keep"], "Keep button")
        expectUsable(app.buttons["swipe.delete"], "Delete button")
        app.goBack()

        app.openTool("blurry")
        sleep(3)
        shot("10 Blurry photos")
        app.goBack()

        app.openTool("compress")
        expectExists(app.all("compressRow").firstMatch, timeout: 20)
        shot("11 Compress videos")
        app.all("compressRow").firstMatch.tap()
        expectExists(app.buttons["quality.small"], timeout: 60)
        shot("12 Compress sheet")
        expectUsable(app.buttons["compress.start"], "Compress button")
        app.buttons["compress.close"].tap()
        app.goBack()

        app.openTool("widget")
        expectExists(app.anyElement("widget.steps"), timeout: 10)
        shot("13 Widget guide")
        app.goBack()

        // First launch.
        app.terminate()
        app = .launchDeclutter(onboarded: false)
        expectExists(app.staticTexts["Give your iPhone some breathing room"], timeout: 20)
        shot("14 Onboarding")
        expectUsable(app.buttons["Continue"], "Continue button")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The element fits the screen's width and can be tapped, scrolling to it if it's further down.
    /// Being below the fold is fine with big text; being wider than the screen, or unreachable, isn't.
    private func expectUsable(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(what) is missing", file: file, line: line)
            return
        }
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(element.frame.minX >= screen.minX && element.frame.maxX <= screen.maxX,
                      "\(what) is cut off: \(element.frame) is wider than \(screen)", file: file, line: line)
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(what) can't be reached", file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.height, screen.height, "\(what) is taller than the screen", file: file, line: line)
    }
}
