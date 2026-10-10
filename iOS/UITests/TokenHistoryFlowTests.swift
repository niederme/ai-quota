import XCTest
final class TokenHistoryFlowTests: XCTestCase {
    func testGraphAndSummaryOpenCodexServiceSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.v1.completed", "NO", "-onboarding.v1.dismissed", "NO", "-onboarding.v1.step", "0"]
        app.launch()
        if app.buttons["Exit demo"].firstMatch.waitForExistence(timeout: 3) { app.buttons["Exit demo"].firstMatch.tap() }
        let demo = app.buttons["Try Demo"].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10)); demo.tap()
        XCTAssertTrue(app.otherElements["tokenActivityGrid"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Token activity"].exists)
        XCTAssertFalse(app.staticTexts["52 weeks"].exists)
        XCTAssertTrue(app.staticTexts["Codex usage reset announced"].exists)
        XCTAssertFalse(app.buttons["Check Codex resets"].exists)
        app.buttons["Dismiss reset announcement"].tap()
        let grid = app.otherElements["tokenActivityGrid"].firstMatch
        if !grid.isHittable { app.swipeUp() }
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertFalse(app.staticTexts["tokenActivityDetail"].exists)
        app.buttons["codexServiceCard"].tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "iOS Codex card opens service sheet"; image.lifetime = .keepAlways; add(image)
    }
}
