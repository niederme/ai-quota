import XCTest

final class MultiAccountFlowTests: XCTestCase {
    func testLiveResetNoticeDismissalPersistsAndSettingsBrowserOpens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-multiAccountResetNoticeUITest", "-resetNoticeClearDismissal"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Codex usage reset announced"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Dismiss reset announcement"].exists)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Live multi-account reset notice"
        overview.lifetime = .keepAlways
        add(overview)

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Read more on Codex Resets")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let resets = app.buttons["Codex Resets"]
        for _ in 0..<5 where !resets.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(resets.isHittable)
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "Multi-account Settings Codex Resets link"
        settings.lifetime = .keepAlways
        add(settings)
        resets.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.buttons["Close"].firstMatch.tap()

        app.buttons["Dismiss reset announcement"].tap()
        XCTAssertFalse(app.staticTexts["Codex usage reset announced"].exists)
        app.terminate()
        app.launchArguments = ["-multiAccountResetNoticeUITest"]
        app.launch()
        XCTAssertTrue(app.buttons["codexServiceCard"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Codex usage reset announced"].exists)
    }

    func testInapplicableStaleAndClaudeOnlyDoNotShowResetNotice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for state in ["-resetNoticeInapplicable", "-resetNoticeStale", "-resetNoticeNoCodex"] {
            app.launchArguments = ["-multiAccountResetNoticeUITest", "-resetNoticeClearDismissal", state]
            app.launch()
            XCTAssertTrue(app.buttons["claudeServiceCard"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Codex usage reset announced"].exists, state)
            if state == "-resetNoticeNoCodex" {
                XCTAssertFalse(app.buttons["codexServiceCard"].exists)
                app.buttons["Settings"].tap()
                XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
                let resets = app.buttons["Codex Resets"]
                for _ in 0..<5 where !resets.exists { app.collectionViews.firstMatch.swipeUp() }
                XCTAssertTrue(resets.exists)
            }
            app.terminate()
        }
    }

    func testBusinessMonthlyResetAppearsWithNeutralCredits() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-businessMonthlyOverviewUITest"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Business plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["credits this month"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Monthly resets")
        ).firstMatch.exists)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Business monthly reset and credits"
        overview.lifetime = .keepAlways
        add(overview)
    }

    func testDefaultOverviewOmitsGenericNumberedAccountLabels() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-genericAccountLabelsUITest"]
        app.launch()

        XCTAssertTrue(app.buttons.matching(identifier: "codexServiceCard").element(boundBy: 0).waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "codexServiceCard").count, 2)
        XCTAssertEqual(app.buttons.matching(identifier: "claudeServiceCard").count, 2)
        XCTAssertTrue(app.staticTexts["Demo plan"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Demo plan · Account 1"].exists)
        XCTAssertFalse(app.staticTexts["Demo plan · Account 2"].exists)
        XCTAssertFalse(app.staticTexts["Demo plan · Service 1"].exists)
        XCTAssertFalse(app.staticTexts["Demo plan · Service 2"].exists)

        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Overview without generic numbered labels"
        overview.lifetime = .keepAlways
        add(overview)
        app.scrollViews.firstMatch.swipeUp()
        let lowerCards = XCTAttachment(screenshot: app.screenshot())
        lowerCards.name = "Four-account overview lower cards"
        lowerCards.lifetime = .keepAlways
        add(lowerCards)
    }

    func testAccountCardDragInterleavesServicesAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-multiAccountReorderUITest", "-resetMultiAccountReorderFixture"]
        app.launch()

        let codexCards = app.buttons.matching(identifier: "codexServiceCard")
        let claudeCard = app.buttons["claudeServiceCard"]
        XCTAssertTrue(app.staticTexts["Demo plan · Personal"].waitForExistence(timeout: 10))
        XCTAssertEqual(codexCards.count, 2)
        XCTAssertTrue(claudeCard.exists)
        XCTAssertFalse(app.buttons["Add Codex account"].exists)
        XCTAssertFalse(app.buttons["Add Claude account"].exists)
        XCTAssertLessThan(codexCards.element(boundBy: 1).frame.midY, claudeCard.frame.midY)

        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 where !claudeCard.isHittable || !codexCards.element(boundBy: 1).isHittable {
            scroll.swipeUp()
        }
        XCTAssertTrue(claudeCard.isHittable)
        XCTAssertTrue(codexCards.element(boundBy: 1).isHittable)
        claudeCard.press(forDuration: 1.1, thenDragTo: codexCards.element(boundBy: 1))
        XCTAssertLessThan(claudeCard.frame.midY, codexCards.element(boundBy: 1).frame.midY)

        app.buttons["Refresh usage"].tap()
        XCTAssertLessThan(claudeCard.frame.midY, codexCards.element(boundBy: 1).frame.midY)
        let reordered = XCTAttachment(screenshot: app.screenshot())
        reordered.name = "Claude card between Codex accounts"
        reordered.lifetime = .keepAlways
        add(reordered)

        claudeCard.tap()
        XCTAssertTrue(app.staticTexts["Enterprise · Demo plan"].waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        app.terminate()
        app.launchArguments = ["-multiAccountReorderUITest"]
        app.launch()
        let restoredCodex = app.buttons.matching(identifier: "codexServiceCard")
        let restoredClaude = app.buttons["claudeServiceCard"]
        XCTAssertTrue(restoredClaude.waitForExistence(timeout: 10))
        XCTAssertLessThan(restoredCodex.element(boundBy: 0).frame.midY, restoredClaude.frame.midY)
        XCTAssertLessThan(restoredClaude.frame.midY, restoredCodex.element(boundBy: 1).frame.midY)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertFalse(app.buttons["Move earlier"].exists)
        XCTAssertFalse(app.buttons["Move later"].exists)
    }

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
        let start = settingsList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = settingsList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
        for _ in 0..<8 where !addClaude.isHittable {
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(addClaude.isHittable)
        addClaude.tap()
        XCTAssertTrue(app.navigationBars["Demo account"].waitForExistence(timeout: 5))
    }
}
