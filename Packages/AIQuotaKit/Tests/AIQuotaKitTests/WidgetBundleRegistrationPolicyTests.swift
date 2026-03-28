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
}
