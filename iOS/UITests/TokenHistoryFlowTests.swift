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
        for month in ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] {
            XCTAssertFalse(app.staticTexts[month].exists)
        }
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


extension TokenHistoryFlowTests {
    func testWideCardsPlaceHistoryUnderDetailsBesideLargerDial() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-multiAccountUITest"]
        app.launch()
        let card = app.buttons.matching(identifier: "codexServiceCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        if min(app.frame.width, app.frame.height) > 600 {
            XCUIDevice.shared.orientation = .landscapeLeft
            // Rotation and navigation-bar visibility settle asynchronously on iPad.
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height && card.frame.width >= 600
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        }
        defer { XCUIDevice.shared.orientation = .portrait }
        let dial = card.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Codex allowance used")).firstMatch
        let graph = card.descendants(matching: .any).matching(identifier: "tokenActivityGrid").firstMatch
        XCTAssertTrue(dial.exists)
        XCTAssertTrue(graph.exists)
        let title = card.staticTexts["Codex"]
        if card.frame.width >= 600 {
            XCTAssertGreaterThan(dial.frame.width, 140)
            XCTAssertGreaterThan(graph.frame.minX, dial.frame.maxX)
            XCTAssertEqual(graph.frame.minX, title.frame.minX, accuracy: 2)
            XCTAssertEqual(graph.frame.maxX, card.frame.maxX - 20, accuracy: 2)
            XCTAssertGreaterThanOrEqual(graph.frame.minX - dial.frame.maxX, 30)
            XCTAssertLessThanOrEqual(graph.frame.height, 70)
        } else {
            XCTAssertLessThan(dial.frame.width, 130)
            XCTAssertGreaterThan(graph.frame.minY, dial.frame.maxY)
        }
        XCTAssertLessThanOrEqual(graph.frame.maxX, card.frame.maxX)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Responsive account card proportions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        graph.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
    }
}
