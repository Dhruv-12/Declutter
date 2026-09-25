import XCTest

/// Permissions set with `xcrun simctl privacy` by Scripts/run-tests.sh. The app must never crash.
final class PermissionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Phase "permissions-ask": nothing decided yet. Deny Photos, allow Contacts from onboarding.
    func testFirstLaunchAsksForAccess() throws {
        try Phase.require("permissions-ask")
        let app = XCUIApplication.launchDeclutter(onboarded: false)
        expectExists(app.staticTexts["Give your iPhone some breathing room"], timeout: 20)

        app.buttons.matching(NSPredicate(format: "label == 'Allow'")).element(boundBy: 0).tap()
        answerSystemAlert(preferring: ["Don’t Allow", "Don't Allow"])
        expectExists(app.buttons["Settings"], timeout: 10, "Denied Photos should offer Settings")

        app.buttons.matching(NSPredicate(format: "label == 'Allow'")).element(boundBy: 0).tap()
        answerSystemAlert(preferring: ["Allow Full Access", "Allow", "Continue", "OK"], repeats: 3)

        app.buttons["Continue"].tap()
        expectExists(app.category("screenshots"), timeout: 20)
        expectExists(app.staticTexts["Photo access is off"])
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Phase "permissions-denied": both revoked.
    func testDeniedAccessNeverCrashes() throws {
        try Phase.require("permissions-denied")
        let app = XCUIApplication.launchDeclutter()
        expectExists(app.staticTexts["Photo access is off"], timeout: 20)
        expectExists(app.staticTexts["Contacts access is off"])

        for category in ["screenshots", "largeVideos", "similarPhotos"] {
            app.openCategory(category)
            expectExists(app.staticTexts["Photo access is off"], timeout: 10, "\(category) should explain access is off")
            expectExists(app.buttons["Open Settings"])
            app.goBack()
        }
        app.openCategory("duplicateContacts")
        expectExists(app.staticTexts["Contacts access is off"], timeout: 10)
        app.goBack()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Phase "permissions-granted": granted after being denied, with the standard library.
    func testGrantedAccessShowsContent() throws {
        try Phase.require("permissions-granted")
        let app = XCUIApplication.launchDeclutter()
        waitForLabel(app.category("screenshots"), contains: "5 screenshots", timeout: 30)
        waitForLabel(app.category("largeVideos"), contains: "3 videos", timeout: 30)
        waitForLabel(app.category("duplicateContacts"), contains: "3 duplicates", timeout: 30)
        XCTAssertFalse(app.staticTexts["Photo access is off"].exists)
        XCTAssertFalse(app.staticTexts["Contacts access is off"].exists)
    }

    private func answerSystemAlert(preferring labels: [String], repeats: Int = 1) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<repeats {
            let deadline = Date().addingTimeInterval(8)
            var answered = false
            while !answered && Date() < deadline {
                for label in labels where springboard.buttons[label].exists {
                    springboard.buttons[label].tap()
                    answered = true
                    break
                }
                if !answered { usleep(250_000) }
            }
            if !answered { break }
            sleep(1)
        }
    }
}

/// Edge cases, each with its own library prepared by Scripts/run-tests.sh.
final class EdgeCaseUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Phase "empty": no photos, videos or duplicate contacts.
    func testEmptyLibrary() throws {
        try Phase.require("empty")
        let app = XCUIApplication.launchDeclutter()
        waitForLabel(app.category("screenshots"), contains: "0 screenshots", timeout: 30)
        waitForLabel(app.category("largeVideos"), contains: "0 videos", timeout: 30)

        app.openCategory("screenshots")
        expectExists(app.staticTexts["No screenshots"])
        XCTAssertFalse(app.reviewBar.exists, "No review bar without anything to review")
        app.goBack()
        app.openCategory("largeVideos")
        expectExists(app.staticTexts["No videos"])
        app.goBack()
        app.openCategory("similarPhotos")
        expectExists(app.staticTexts["No similar photos"], timeout: 60)
        app.goBack()
        app.openCategory("duplicateContacts")
        expectExists(app.staticTexts["No duplicate contacts"], timeout: 30)
        app.goBack()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Phase "unique": photos and contacts, but nothing is a duplicate.
    func testZeroDuplicates() throws {
        try Phase.require("unique")
        let app = XCUIApplication.launchDeclutter()
        app.openCategory("similarPhotos")
        expectExists(app.staticTexts["No similar photos"], timeout: 120)
        app.goBack()
        app.openCategory("duplicateContacts")
        expectExists(app.staticTexts["No duplicate contacts"], timeout: 30)
        app.goBack()
        waitForLabel(app.category("similarPhotos"), contains: "0 extra photos")
        waitForLabel(app.category("duplicateContacts"), contains: "0 duplicates")
    }

    /// Phase "large": 1,500 photos with 30 planted near-duplicate pairs.
    func testLargeLibrary() throws {
        try Phase.require("large")
        let app = XCUIApplication.launchDeclutter()
        let start = Date()
        app.openCategory("similarPhotos")
        // The scan must finish, find the planted pairs, and keep the app responsive.
        waitForLabel(app.screenSummary, startsWith: "30 sets · 30 extra photos", timeout: 900)
        let seconds = Int(Date().timeIntervalSince(start))
        print("Large library: similar-photo scan finished in about \(seconds) s")
        XCTContext.runActivity(named: "Scan of 1,530 photos took about \(seconds) s") { _ in }

        app.swipeUp()
        app.swipeUp()
        app.goBack()
        app.openCategory("screenshots")
        expectExists(app.staticTexts["No screenshots"])
        app.goBack()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
