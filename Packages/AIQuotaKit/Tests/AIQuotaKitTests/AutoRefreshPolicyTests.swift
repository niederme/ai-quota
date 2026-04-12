import XCTest
@testable import AIQuotaKit

final class AutoRefreshPolicyTests: XCTestCase {
    func testActiveAppRefreshesEveryMinute() {
        let interval = AutoRefreshPolicy.interval(for: makeContext(appIsActive: true))
        XCTAssertEqual(interval, 60, accuracy: 0.5)
    }

    func testNearThresholdRefreshesEveryMinute() {
        let interval = AutoRefreshPolicy.interval(
            for: makeContext(appIsActive: false, codexNearThreshold: true)
        )
        XCTAssertEqual(interval, 60, accuracy: 0.5)
    }

    func testNormalIdleUseRefreshesEveryFiveMinutes() {
        let interval = AutoRefreshPolicy.interval(for: makeContext(machineIdleSeconds: 120))
        XCTAssertEqual(interval, 300, accuracy: 0.5)
    }

    func testLongerIdleUseBacksOffToTenThenFifteenMinutes() {
        let tenMinuteInterval = AutoRefreshPolicy.interval(for: makeContext(machineIdleSeconds: 600))
        XCTAssertEqual(tenMinuteInterval, 600, accuracy: 0.5)

        let fifteenMinuteInterval = AutoRefreshPolicy.interval(for: makeContext(machineIdleSeconds: 1_200))
        XCTAssertEqual(fifteenMinuteInterval, 900, accuracy: 0.5)
    }

    func testOfflineOrLowPowerBacksOffToThirtyMinutes() {
        let offlineInterval = AutoRefreshPolicy.interval(for: makeContext(networkAvailable: false))
        XCTAssertEqual(offlineInterval, 1_800, accuracy: 0.5)

        let lowPowerInterval = AutoRefreshPolicy.interval(for: makeContext(lowPowerModeEnabled: true))
        XCTAssertEqual(lowPowerInterval, 1_800, accuracy: 0.5)
    }

    private func makeContext(
        appIsActive: Bool = false,
        lowPowerModeEnabled: Bool = false,
        networkAvailable: Bool = true,
        machineIdleSeconds: TimeInterval = 0,
        hasCachedUsageData: Bool = true,
        codexNearThreshold: Bool = false,
        claudeNearThreshold: Bool = false
    ) -> AutoRefreshContext {
        AutoRefreshContext(
            appIsActive: appIsActive,
            lowPowerModeEnabled: lowPowerModeEnabled,
            networkAvailable: networkAvailable,
            machineIdleSeconds: machineIdleSeconds,
            hasCachedUsageData: hasCachedUsageData,
            codexNearThreshold: codexNearThreshold,
            claudeNearThreshold: claudeNearThreshold
        )
    }
}
