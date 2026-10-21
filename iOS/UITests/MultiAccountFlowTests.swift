import XCTest

final class MultiAccountFlowTests: XCTestCase {
    func testStackedCardsRouteToSelectedAccountAndSettingsCanAdd() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-multiAccountUITest"]
        app.launch()

        let codexCards = app.buttons.matching(identifier: "codexServiceCard")
        XCTAssertTrue(app.staticTexts["Demo plan · Personal"].waitForExistence(timeout: 10))
        XCTAssertEqual(codexCards.count, 2)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Two Codex accounts stacked above Claude"
        overview.lifetime = .keepAlways
        add(overview)

        codexCards.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Work · Demo plan"].waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()

        app.buttons["Settings"].tap()
        let settingsList = app.collectionViews.firstMatch
        let addClaude = settingsList.buttons["Add Claude account"]
        XCTAssertTrue(addClaude.waitForExistence(timeout: 5))
        for _ in 0..<4 where !addClaude.isHittable { settingsList.swipeUp() }
        XCTAssertTrue(addClaude.isHittable)
        addClaude.tap()
        XCTAssertTrue(app.navigationBars["Demo account"].waitForExistence(timeout: 5))
    }
}
