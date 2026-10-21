import XCTest

@MainActor final class ClaudeDetailReconnectFlowTests: XCTestCase {
    func testSuccessfulWebSignInKeepsDetailsOnDismissAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-claudeSSOUITest"]
        app.launch()

        let open = app.buttons["Open Claude details"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let alert = app.alerts["Reconnect Claude"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Reconnect"].tap()

        XCTAssertTrue(app.staticTexts["Spend by product"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["Skills"].exists)
        XCTAssertTrue(app.staticTexts["sample-skill"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UTC")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Loading Claude details…"].exists)
        XCTAssertTrue(app.staticTexts["Sign in to Claude"].waitForNonExistence(timeout: 10))
        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Claude Enterprise detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)

        app.buttons["Close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.staticTexts["Spend by product"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Reconnect Claude"].exists)
    }

    func testUnavailableRetryOffersActionableReconnect() {
        let app = XCUIApplication()
        app.launchArguments = ["-claudeDetailUITest"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Claude details unavailable"].waitForExistence(timeout: 10))
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.exists)
        retry.tap()

        let alert = app.alerts["Reconnect Claude"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        alert.buttons["Cancel"].tap()

        // Dismissing the one-time prompt leaves an actionable path in the view.
        let reconnect = app.buttons["Reconnect"]
        XCTAssertTrue(reconnect.waitForExistence(timeout: 5))
        reconnect.tap()
        XCTAssertTrue(app.staticTexts["Connect Claude"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Continue Claude sign-in"].exists)
        app.buttons["Continue Claude sign-in"].tap()
        XCTAssertTrue(app.navigationBars["Sign in with Claude"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Use Safari"].exists)
    }

    func testServiceDetailLoadingSkeletonsReserveHistoryGeometry() {
        let codex = XCUIApplication()
        codex.launchArguments = ["-serviceDetailLoadingUITest"]
        codex.launch()
        XCTAssertTrue(codex.otherElements["codexHistoryLoadingSkeleton"].waitForExistence(timeout: 10))
        XCTAssertFalse(codex.staticTexts["Monthly allowance"].exists)
        XCTAssertFalse(codex.staticTexts["History not reported"].exists)
        codex.terminate()

        let claude = XCUIApplication()
        claude.launchArguments = ["-serviceDetailLoadingUITest", "-claudeService"]
        claude.launch()
        XCTAssertTrue(claude.otherElements["claudeBreakdownLoadingSkeleton"].waitForExistence(timeout: 10))
        XCTAssertFalse(claude.staticTexts["Weekly breakdown unavailable"].exists)
        XCTAssertFalse(claude.staticTexts["Spending not reported"].exists)
    }

    func testClaudeEnterpriseLoadingUsesStableSkeleton() {
        let app = XCUIApplication()
        app.launchArguments = ["-claudeEnterpriseLoadingUITest"]
        app.launch()

        XCTAssertTrue(app.otherElements["claudeEnterpriseLoadingSkeleton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No spend history reported"].exists)
        XCTAssertFalse(app.staticTexts["No skill activity reported"].exists)
    }

    func testCodexHistoryHasOnePeriodTotalAndVisibleCoverage() {
        let app = XCUIApplication()
        app.launchArguments = ["-codexHistoryVisualUITest"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Daily usage"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "86.23 usage credits")).count, 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "5 of 7 calendar days reported")).firstMatch.exists)
        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Codex daily history"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["By model"].exists)
        XCTAssertTrue(app.staticTexts["By app"].exists)
    }

    func testCodexThirtyDayCoverageAtAccessibilitySize() {
        let app = XCUIApplication()
        app.launchArguments = ["-codexHistoryVisualUITest", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()

        XCTAssertTrue(app.buttons["30 days"].waitForExistence(timeout: 10))
        app.buttons["30 days"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "5 of 30 calendar days reported")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "86.23 usage credits")).count, 1)
        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Codex 30-day accessibility history"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }
}
