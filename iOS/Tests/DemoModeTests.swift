import XCTest
import MobileAccessCore
@testable import AIQuota_iOS

@MainActor
final class DemoModeTests: XCTestCase {
    func testDemoSetupDoesNotChangeRealOnboardingProgress() {
        let suite = "demo-setup-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let live = OnboardingProgress(defaults: defaults)
        live.setStep(.services)
        let before = defaults.dictionaryRepresentation()
        let demo = OnboardingProgress(defaults: defaults, isDemo: true)
        demo.replay()
        XCTAssertEqual(demo.step, .welcome)
        for step in OnboardingProgress.order { demo.setStep(step) }
        demo.finish()
        demo.reset()
        XCTAssertEqual(NSDictionary(dictionary: defaults.dictionaryRepresentation()), NSDictionary(dictionary: before))
        XCTAssertEqual(live.step, .services)
    }

    func testDemoFixturesHaveDistinctWindowsAndThirtyDaysOfHistory() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let codex = DemoQuotaData.reading(.codex, now: now)
        let claude = DemoQuotaData.reading(.claude, now: now)
        XCTAssertEqual(codex.shortTerm?.usedPercent, 38)
        XCTAssertEqual(claude.shortTerm?.usedPercent, 72)
        XCTAssertEqual(codex.weekly?.usedPercent, 61)
        XCTAssertEqual(claude.weekly?.usedPercent, 44)
        XCTAssertEqual(codex.shortTerm?.resetsAt, now.addingTimeInterval(7200))
        XCTAssertEqual(codex.metadata?.plan, "Demo")
        let history = DemoQuotaData.history(now: now)
        XCTAssertEqual(history.days.count, 30)
        XCTAssertTrue(history.days.allSatisfy { ($0.credits ?? 0) > 0 })
        XCTAssertEqual(history.days.last?.date, CodexUsageHistory.dateString(now))
    }

    func testDemoModelsCannotStartAuthenticationOrClearSavedReadings() async throws {
        let keys = ["mobileProbe.codexReading", "mobileProbe.claudeReading", "mobileProbe.codexHistory"]
        let saved = keys.map { UserDefaults.standard.data(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        }
        let sentinel = Data("existing live cache".utf8)
        for key in keys { UserDefaults.standard.set(sentinel, forKey: key) }
        let codex = ProbeModel(isDemo: true)
        let claude = ClaudeProbeModel(isDemo: true)
        codex.connect()
        claude.connect()
        claude.finishSignIn("not-a-real-code")
        XCTAssertNil(codex.challenge)
        XCTAssertNil(claude.challenge)
        XCTAssertFalse(codex.busy)
        XCTAssertFalse(claude.busy)
        await codex.refreshAndWait()
        await claude.refreshAndWait()
        codex.disconnect()
        claude.disconnect()
        try await codex.resetForNewUser()
        try await claude.resetForNewUser()
        XCTAssertTrue(codex.connected)
        XCTAssertTrue(claude.connected)
        XCTAssertEqual(codex.reading?.metadata?.plan, "Demo")
        XCTAssertEqual(claude.reading?.metadata?.plan, "Demo")
        for key in keys { XCTAssertEqual(UserDefaults.standard.data(forKey: key), sentinel) }
    }
}
