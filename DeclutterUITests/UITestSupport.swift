import XCTest

/// Scripts/run-tests.sh prepares the simulator for one phase at a time (seeded library, denied
/// permissions, empty library, …) and passes the phase name. Tests for other phases skip themselves.
enum Phase {
    static var current: String? { ProcessInfo.processInfo.environment["DECLUTTER_PHASE"] }

    static func require(_ name: String) throws {
        guard current == name else {
            throw XCTSkip("Runs in the \"\(name)\" phase of Scripts/run-tests.sh (current: \(current ?? "none")).")
        }
    }
}

extension XCUIApplication {
    /// Launches Declutter without the intro. `onboarded: false` shows the first-run screen.
    static func launchDeclutter(onboarded: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-skipIntro", "YES", "-hasFinishedOnboarding", onboarded ? "YES" : "NO"]
        app.launch()
        return app
    }

    var reviewBar: XCUIElement { buttons["reviewBar"] }
    var screenSummary: XCUIElement { staticTexts["screenSummary"] }

    func anyElement(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func all(_ identifier: String) -> XCUIElementQuery {
        descendants(matching: .any).matching(identifier: identifier)
    }

    func button(startingWith prefix: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func text(containing text: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func category(_ name: String) -> XCUIElement { anyElement("category.\(name)") }

    func openCategory(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = category(name)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Home row for \(name) missing", file: file, line: line)
        row.tap()
    }

    func goBack() {
        navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Taps a button in a confirmation dialog or alert shown by the app.
    func tapDialogButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            for query in [sheets.buttons, alerts.buttons, collectionViews.buttons] where query[label].exists {
                query[label].tap()
                return
            }
            // iOS may show a dialog as a popover: take the last matching button that isn't a screen button.
            let matches = buttons.matching(NSPredicate(format: "label == %@ AND identifier == ''", label))
            if matches.count > 0, matches.element(boundBy: matches.count - 1).isHittable {
                matches.element(boundBy: matches.count - 1).tap()
                return
            }
            usleep(250_000)
        }
        XCTFail("Dialog button \"\(label)\" never appeared", file: file, line: line)
    }

    /// Approves the iOS "Allow Declutter to delete…" prompt shown for photo deletes.
    func confirmSystemDelete(file: StaticString = #filePath, line: UInt = #line) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            for query in [alerts.buttons, springboard.alerts.buttons, springboard.buttons] where query["Delete"].exists {
                query["Delete"].tap()
                return
            }
            usleep(250_000)
        }
        XCTFail("The iOS delete confirmation never appeared", file: file, line: line)
    }
}

extension XCTestCase {
    /// Waits until the element's label starts with `prefix`.
    func waitForLabel(_ element: XCUIElement, startsWith prefix: String, timeout: TimeInterval = 15,
                      file: StaticString = #filePath, line: UInt = #line) {
        wait(element, NSPredicate(format: "exists == true AND label BEGINSWITH %@", prefix), timeout, file, line,
             "label starting \"\(prefix)\"")
    }

    /// Waits until the element's label contains `text`.
    func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 15,
                      file: StaticString = #filePath, line: UInt = #line) {
        wait(element, NSPredicate(format: "exists == true AND label CONTAINS %@", text), timeout, file, line,
             "label containing \"\(text)\"")
    }

    private func wait(_ element: XCUIElement, _ predicate: NSPredicate, _ timeout: TimeInterval,
                      _ file: StaticString, _ line: UInt, _ what: String) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        if XCTWaiter.wait(for: [expectation], timeout: timeout) != .completed {
            let actual = element.exists ? "\"\(element.label)\"" : "element missing"
            XCTFail("Expected \(what), got \(actual)", file: file, line: line)
        }
    }

    /// Asserts a thing exists within `timeout`.
    func expectExists(_ element: XCUIElement, timeout: TimeInterval = 15, _ message: String = "",
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message, file: file, line: line)
    }

    /// Checks the summary after a delete, then goes back home.
    func finishOnSummary(_ app: XCUIApplication, removed: String, file: StaticString = #filePath, line: UInt = #line) {
        let backHome = app.buttons["summary.backHome"]
        expectExists(backHome, timeout: 30, "Space freed summary didn't appear", file: file, line: line)
        expectExists(app.text(containing: removed), timeout: 2, "Summary should list \"\(removed)\"", file: file, line: line)
        backHome.tap()
        XCTAssertTrue(backHome.waitForNonExistence(timeout: 10), "Summary didn't close", file: file, line: line)
    }
}
