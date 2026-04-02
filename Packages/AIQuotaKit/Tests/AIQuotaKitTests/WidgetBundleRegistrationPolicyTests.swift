import XCTest
@testable import AIQuotaKit

final class WidgetBundleRegistrationPolicyTests: XCTestCase {
    func testDoesNotRepairWhenBundleVersionAndPathMatchPreviousRegistration() {
        XCTAssertFalse(WidgetBundleRegistrationPolicy.shouldRepair(
            currentVersion: "289",
            currentPath: "/Applications/AIQuota.app",
            lastRegisteredVersion: "289",
            lastRegisteredPath: "/Applications/AIQuota.app"
        ))
    }

    func testRepairsWhenBundleVersionChanges() {
        XCTAssertTrue(WidgetBundleRegistrationPolicy.shouldRepair(
            currentVersion: "290",
            currentPath: "/Applications/AIQuota.app",
            lastRegisteredVersion: "289",
            lastRegisteredPath: "/Applications/AIQuota.app"
        ))
    }

    func testRepairsWhenBundlePathChanges() {
        XCTAssertTrue(WidgetBundleRegistrationPolicy.shouldRepair(
            currentVersion: "289",
            currentPath: "/Applications/AIQuota.app",
            lastRegisteredVersion: "289",
            lastRegisteredPath: "/Users/niederme/Desktop/AIQuota.app"
        ))
    }

    func testDoesNotRestartWidgetHostsWhenBundleVersionAndPathMatchPreviousRestart() {
        XCTAssertFalse(WidgetBundleRegistrationPolicy.shouldRestartWidgetHosts(
            currentVersion: "289",
            currentPath: "/Applications/AIQuota.app",
            lastRestartedVersion: "289",
            lastRestartedPath: "/Applications/AIQuota.app"
        ))
    }

    func testRestartsWidgetHostsWhenBundleVersionChanges() {
        XCTAssertTrue(WidgetBundleRegistrationPolicy.shouldRestartWidgetHosts(
            currentVersion: "290",
            currentPath: "/Applications/AIQuota.app",
            lastRestartedVersion: "289",
            lastRestartedPath: "/Applications/AIQuota.app"
        ))
    }

    func testRestartsWidgetHostsWhenBundlePathChanges() {
        XCTAssertTrue(WidgetBundleRegistrationPolicy.shouldRestartWidgetHosts(
            currentVersion: "289",
            currentPath: "/Applications/AIQuota.app",
            lastRestartedVersion: "289",
            lastRestartedPath: "/Users/niederme/Desktop/AIQuota.app"
        ))
    }
}
