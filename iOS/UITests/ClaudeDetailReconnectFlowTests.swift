import XCTest

final class ClaudeDetailReconnectFlowTests: XCTestCase {
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
        XCTAssertTrue(app.buttons["Open Claude sign-in"].exists)
    }
}
