import XCTest

final class DemoFlowTests: XCTestCase {
    func testEnterAndExitDemoFromWelcomeAndSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.v1.completed", "NO", "-onboarding.v1.dismissed", "NO", "-onboarding.v1.step", "0"]
        app.launch()
        if app.buttons["Exit demo"].firstMatch.waitForExistence(timeout: 3) {
            app.buttons["Exit demo"].firstMatch.tap()
        }
        let tryDemo = app.buttons["Try demo"].firstMatch
        XCTAssertTrue(tryDemo.waitForExistence(timeout: 10))
        // Verify the real onboarding controls before entering the demo.
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Connect your services"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        tryDemo.tap()
        let sample = app.staticTexts["Sample usage for Codex and Claude."]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        app.buttons["Exit demo"].firstMatch.tap()
        XCTAssertTrue(sample.waitForNonExistence(timeout: 5))
        // A new root dismisses account/settings sheets on both transitions.
        if app.buttons["Not now"].exists { app.buttons["Not now"].tap() }
        app.buttons["Settings"].tap()
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
        finish.tap()
        let exit = app.buttons["Exit demo"].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(sample.exists)
    }
}
