import XCTest
@testable import AIQuotaKit

final class AutoRefreshPolicyTests: XCTestCase {
    func testRecentServiceActivityRefreshesEveryMinute() {
        let interval = AutoRefreshPolicy.interval(for: makeContext(serviceRecentlyActive: true))
        XCTAssertEqual(interval, 60, accuracy: 0.5)
    }

    func testNearThresholdRefreshesEveryMinute() {
        let interval = AutoRefreshPolicy.interval(
            for: makeContext(codexNearThreshold: true)
        )
        XCTAssertEqual(interval, 60, accuracy: 0.5)
    }

    func testNormalMacUseRefreshesEveryFiveMinutes() {
        let interval = AutoRefreshPolicy.interval(for: makeContext(machineIdleSeconds: 120))
        XCTAssertEqual(interval, 300, accuracy: 0.5)
    }

    func testIdleMacBacksOffToTenMinutes() {
        let interval = AutoRefreshPolicy.interval(for: makeContext(machineIdleSeconds: 300))
        XCTAssertEqual(interval, 600, accuracy: 0.5)
    }

    func testOfflineOrLowPowerBacksOffToTenMinutes() {
        let offlineInterval = AutoRefreshPolicy.interval(for: makeContext(networkAvailable: false))
        XCTAssertEqual(offlineInterval, 600, accuracy: 0.5)

        let lowPowerInterval = AutoRefreshPolicy.interval(for: makeContext(lowPowerModeEnabled: true))
        XCTAssertEqual(lowPowerInterval, 600, accuracy: 0.5)
    }

    func testIdleAndPowerSavingOverrideFastModes() {
        let interval = AutoRefreshPolicy.interval(
            for: makeContext(
                lowPowerModeEnabled: true,
                serviceRecentlyActive: true,
                codexNearThreshold: true
            )
        )
        XCTAssertEqual(interval, 600, accuracy: 0.5)
    }

    func testCodexActivityIgnoresFetchTimeAndResetCountdownChanges() {
        let previous = makeCodexUsage(fetchedAt: Date(timeIntervalSince1970: 100))
        let unchanged = makeCodexUsage(
            resetAfterSeconds: 240,
            fetchedAt: Date(timeIntervalSince1970: 160)
        )
        let changed = makeCodexUsage(
            hourlyUsedPercent: 13,
            fetchedAt: Date(timeIntervalSince1970: 160)
        )

        XCTAssertFalse(AutoRefreshActivity.changed(from: previous, to: unchanged))
        XCTAssertTrue(AutoRefreshActivity.changed(from: previous, to: changed))
    }

    func testClaudeActivityTracksUsageButIgnoresFetchTime() {
        let previous = makeClaudeUsage(
            fiveHourUtilization: 12,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let unchanged = makeClaudeUsage(
            fiveHourUtilization: 12,
            fetchedAt: Date(timeIntervalSince1970: 160)
        )
        let changed = makeClaudeUsage(
            fiveHourUtilization: 12.5,
            fetchedAt: Date(timeIntervalSince1970: 160)
        )

        XCTAssertFalse(AutoRefreshActivity.changed(from: previous, to: unchanged))
        XCTAssertTrue(AutoRefreshActivity.changed(from: previous, to: changed))
    }

    private func makeContext(
        lowPowerModeEnabled: Bool = false,
        networkAvailable: Bool = true,
        machineIdleSeconds: TimeInterval = 0,
        serviceRecentlyActive: Bool = false,
        codexNearThreshold: Bool = false,
        claudeNearThreshold: Bool = false
    ) -> AutoRefreshContext {
        AutoRefreshContext(
            lowPowerModeEnabled: lowPowerModeEnabled,
            networkAvailable: networkAvailable,
            machineIdleSeconds: machineIdleSeconds,
            serviceRecentlyActive: serviceRecentlyActive,
            codexNearThreshold: codexNearThreshold,
            claudeNearThreshold: claudeNearThreshold
        )
    }

    private func makeCodexUsage(
        hourlyUsedPercent: Int = 12,
        resetAfterSeconds: Int = 300,
        fetchedAt: Date
    ) -> CodexUsage {
        CodexUsage(
            weeklyUsedPercent: 25,
            weeklyResetAt: Date(timeIntervalSince1970: 10_000),
            weeklyResetAfterSeconds: 9_000,
            hourlyUsedPercent: hourlyUsedPercent,
            hourlyResetAt: Date(timeIntervalSince1970: 1_000),
            hourlyResetAfterSeconds: resetAfterSeconds,
            hourlyWindowSeconds: 18_000,
            limitReached: false,
            allowed: true,
            planType: "plus",
            creditBalance: 100,
            approxLocalMessages: [10, 100],
            approxCloudMessages: [2, 20],
            fetchedAt: fetchedAt
        )
    }

    private func makeClaudeUsage(
        fiveHourUtilization: Double,
        fetchedAt: Date
    ) -> ClaudeUsage {
        ClaudeUsage(
            fiveHourUtilization: fiveHourUtilization,
            fiveHourResetsAt: Date(timeIntervalSince1970: 1_000),
            sevenDayUtilization: 25,
            sevenDayResetsAt: Date(timeIntervalSince1970: 10_000),
            extraUsage: nil,
            planLabel: .pro,
            fetchedAt: fetchedAt
        )
    }
}
