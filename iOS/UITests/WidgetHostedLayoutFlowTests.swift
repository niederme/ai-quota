import XCTest

/// Run on an isolated, English-language simulator: this changes its Home Screen.
/// Captures the real WidgetKit host, including system background treatment.
final class WidgetHostedLayoutFlowTests: XCTestCase {
    @MainActor func testHomeScreenWidgetSizes() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("AIQuota Integration Check") == true,
                          "Use a dedicated AIQuota Integration Check simulator; this test changes its Home Screen.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.v1.completed", "NO", "-onboarding.v1.dismissed", "NO", "-onboarding.v1.step", "0"]
        app.launch()
        if !app.buttons["Exit demo"].firstMatch.exists {
            let demo = app.buttons["Try Demo"].firstMatch
            XCTAssertTrue(demo.waitForExistence(timeout: 10))
            demo.tap()
        }
        XCTAssertTrue(app.staticTexts["Sample usage for Codex and Claude."].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if board.buttons["Continue"].firstMatch.exists { board.buttons["Continue"].firstMatch.tap() }
        let icon = board.icons["AIQuota"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        for (button, name) in [("Small widget", "small"), ("Medium-sized widget", "medium"), ("Large widget", "large")] {
            icon.press(forDuration: 0.8)
            let size = board.buttons[button].firstMatch
            XCTAssertTrue(size.waitForExistence(timeout: 5))
            size.tap()
            try await Task.sleep(for: .seconds(5))
            XCTAssertEqual(icon.value as? String, "Widget")
            print("HOSTED_SIZE \(name): \(icon.frame)")
            let image = XCTAttachment(screenshot: board.screenshot())
            image.name = "Hosted Account \(name) with sample usage"
            image.lifetime = .keepAlways
            add(image)
        }
    }
}
