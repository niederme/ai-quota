import XCTest
final class TokenHistoryFlowTests: XCTestCase {
    func testDefaultCardTapShowsTokenDetailWithoutOpeningServiceSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.v1.completed", "NO", "-onboarding.v1.dismissed", "NO", "-onboarding.v1.step", "0"]
        app.launch()
        if app.buttons["Exit demo"].firstMatch.waitForExistence(timeout: 3) { app.buttons["Exit demo"].firstMatch.tap() }
        let demo = app.buttons["Try Demo"].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10)); demo.tap()
        XCTAssertTrue(app.staticTexts["Token activity"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Codex usage reset announced"].exists)
        XCTAssertFalse(app.buttons["Check Codex resets"].exists)
        app.buttons["Dismiss reset announcement"].tap()
        let grid = app.otherElements["tokenActivityGrid"].firstMatch
        if !grid.isHittable { app.swipeUp() }
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let detail = app.staticTexts["tokenActivityDetail"]
        XCTAssertTrue(detail.exists)
        XCTAssertTrue(detail.label.contains("tokens") || detail.label.contains("no record reported"))
        XCTAssertFalse(app.navigationBars["Codex"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "iOS default card token detail"; image.lifetime = .keepAlways; add(image)
    }
}
