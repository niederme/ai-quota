import XCTest

final class DemoFlowTests: XCTestCase {
    func testDemoReturnsToOnboardingAndSupportsGuidedSetup() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.v1.completed", "NO", "-onboarding.v1.dismissed", "NO", "-onboarding.v1.step", "0"]
        app.launch()
        if app.buttons["Exit demo"].firstMatch.waitForExistence(timeout: 3) {
            app.buttons["Exit demo"].firstMatch.tap()
        }
        let tryDemo = app.buttons["Try Demo"].firstMatch
        XCTAssertTrue(tryDemo.waitForExistence(timeout: 10))
        // Verify the real onboarding controls before entering the demo.
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Connect your services"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["Back"].tap()
        tryDemo.tap()
        let sample = app.staticTexts["Sample usage for Codex and Claude."]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        app.buttons["Exit demo"].firstMatch.tap()
        XCTAssertTrue(sample.waitForNonExistence(timeout: 5))
        // With no live accounts, exiting the demo returns to the existing setup flow.
        XCTAssertTrue(app.navigationBars["Set up AIQuota"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Not now"].exists)
        XCTAssertTrue(tryDemo.waitForExistence(timeout: 5))
        tryDemo.tap()
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["Guided Setup…"].tap()
        XCTAssertTrue(app.navigationBars["Demo setup"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Connect your services"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Demo settings are temporary. No notifications will be sent."].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        let finish = app.buttons["Return to demo"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        let consent = app.switches["analyticsConsent"].firstMatch
        XCTAssertTrue(consent.exists)
        XCTAssertEqual(consent.value as? String, "0")
        consent.tap()
        XCTAssertEqual(consent.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Demo settings are temporary. No usage data will be sent."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Analytics consent in guided setup"
        attachment.lifetime = .keepAlways
        add(attachment)
        finish.tap()
        let exit = app.buttons["Exit demo"].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
        XCTAssertTrue(app.navigationBars["Set up AIQuota"].waitForExistence(timeout: 5))
        XCTAssertFalse(sample.exists)
    }
}
