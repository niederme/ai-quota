import XCTest
import SwiftUI
@testable import AIQuota_iOS

@MainActor
private final class RecordingAnalyticsTransport: MobileAnalyticsTransport {
    var collection: [Bool] = []
    var events: [(name: String, params: [String: String])] = []
    func setCollectionEnabled(_ enabled: Bool) { collection.append(enabled) }
    func send(_ event: String, params: [String: String]) { events.append((event, params)) }
}

@MainActor
final class MobileAnalyticsTests: XCTestCase {
    private func isolated(_ body: (UserDefaults, RecordingAnalyticsTransport) -> Void) {
        let suite = "analytics-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults, RecordingAnalyticsTransport())
    }

    func testFreshAndExistingInstallsStaySilentWithoutConsent() {
        isolated { defaults, transport in
            defaults.set(true, forKey: "onboarding.v1.completed")
            let analytics = MobileAnalytics(defaults: defaults, transport: transport)
            analytics.observeServices(codex: true, claude: false, isDemo: false)
            analytics.recordLaunchIfNeeded()
            analytics.recordDailyActiveIfNeeded()
            analytics.completeOnboarding()
            analytics.manualRefresh()
            XCTAssertFalse(analytics.isEnabled)
            XCTAssertEqual(transport.collection, [false])
            XCTAssertTrue(transport.events.isEmpty)
            XCTAssertNil(defaults.object(forKey: MobileAnalytics.lastActiveDateKey))
        }
    }

    func testOptInPersistsAndOptOutImmediatelyStopsEvents() {
        isolated { defaults, transport in
            let analytics = MobileAnalytics(defaults: defaults, transport: transport)
            analytics.setEnabled(true, surface: .onboarding)
            XCTAssertTrue(defaults.bool(forKey: MobileAnalytics.enabledKey))
            XCTAssertEqual(transport.events.map(\.name), ["analytics_enabled", "app_active"])
            XCTAssertEqual(transport.events.first?.params["consent_surface"], "onboarding")
            let restored = MobileAnalytics(defaults: defaults, transport: transport)
            XCTAssertTrue(restored.isEnabled)
            restored.setEnabled(false, surface: .settings)
            let count = transport.events.count
            restored.manualRefresh()
            restored.completeOnboarding()
            restored.recordLaunchIfNeeded()
            XCTAssertEqual(transport.events.count, count)
            XCTAssertEqual(transport.collection.last, false)
        }
    }

    func testDailyActiveDeduplicatesAcrossRelaunchAndAdvancesOnNextUTCDay() {
        isolated { defaults, transport in
            defaults.set(true, forKey: MobileAnalytics.enabledKey)
            var date = Date(timeIntervalSince1970: 1_800_000_000)
            let analytics = MobileAnalytics(defaults: defaults, transport: transport, now: { date })
            analytics.recordLaunchIfNeeded()
            analytics.recordLaunchIfNeeded()
            analytics.recordDailyActiveIfNeeded()
            let restored = MobileAnalytics(defaults: defaults, transport: transport, now: { date })
            restored.recordDailyActiveIfNeeded()
            XCTAssertEqual(transport.events.filter { $0.name == "app_launched" }.count, 1)
            XCTAssertEqual(transport.events.filter { $0.name == "app_active" }.count, 1)
            date.addTimeInterval(86_400)
            restored.recordDailyActiveIfNeeded()
            XCTAssertEqual(transport.events.filter { $0.name == "app_active" }.count, 2)
        }
    }

    func testDemoPreservesConsentAndSuppressesEveryEvent() {
        isolated { defaults, transport in
            defaults.set(true, forKey: MobileAnalytics.enabledKey)
            let analytics = MobileAnalytics(defaults: defaults, transport: transport, isDemo: true)
            analytics.observeServices(codex: true, claude: true, isDemo: true)
            analytics.recordLaunchIfNeeded()
            analytics.manualRefresh()
            analytics.completeOnboarding()
            analytics.setEnabled(false, surface: .settings)
            XCTAssertTrue(analytics.isEnabled)
            XCTAssertTrue(transport.events.isEmpty)
            XCTAssertEqual(transport.collection, [false])
            analytics.observeServices(codex: true, claude: false, isDemo: false)
            analytics.recordDailyActiveIfNeeded()
            XCTAssertEqual(transport.collection.last, true)
            XCTAssertEqual(transport.events.map(\.name), ["app_active"])
            XCTAssertEqual(transport.events.last?.params["services"], "codex")
        }
    }

    func testRestoringAccountsIsNotAConnectionAndPayloadContainsOnlyProductState() {
        isolated { defaults, transport in
            defaults.set(true, forKey: MobileAnalytics.enabledKey)
            let analytics = MobileAnalytics(defaults: defaults, transport: transport, appVersion: "0.1.0")
            analytics.observeServices(codex: true, claude: false, isDemo: false)
            XCTAssertTrue(transport.events.isEmpty)
            analytics.observeServices(codex: true, claude: true, isDemo: false)
            XCTAssertEqual(transport.events.last?.name, "service_connected")
            XCTAssertEqual(transport.events.last?.params, ["platform": "ios", "app_version": "0.1.0",
                "services": "both", "service_count": "2", "onboarding_completed": "false",
                "service": "claude", "services_after_connect": "both"])
            analytics.observeServices(codex: false, claude: true, isDemo: false)
            XCTAssertEqual(transport.events.last?.name, "service_disconnected")
            XCTAssertEqual(transport.events.last?.params["service"], "codex")
            defaults.set(true, forKey: "onboarding.v1.completed")
            analytics.completeOnboarding()
            XCTAssertEqual(transport.events.last?.params["onboarding_completed"], "true")
        }
    }

    func testConsentCardAtNarrowWidthAndAccessibilityText() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for size in [DynamicTypeSize.large, .accessibility1] {
            let content = VStack(alignment: .leading, spacing: 12) {
                MobileAnalyticsConsentControls(surface: .onboarding)
            }.padding(18).frame(width: 320)
                .background(OverviewStyle.track)
                .foregroundStyle(OverviewStyle.primary)
                .tint(OverviewStyle.accent)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, size)
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = UIHostingController(rootView:
                content.frame(maxWidth: .infinity, maxHeight: .infinity).background(OverviewStyle.base)
                    .environment(\.colorScheme, .dark))
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Analytics consent \(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("analytics-consent-\(size).png")
            try image.pngData()?.write(to: path)
            print("ANALYTICS_REVIEW " + path.path)
        }
    }

    func testResetRevokesConsentAndClearsDailyMarker() {
        isolated { defaults, transport in
            let analytics = MobileAnalytics(defaults: defaults, transport: transport)
            analytics.setEnabled(true, surface: .settings)
            analytics.reset()
            XCTAssertFalse(analytics.isEnabled)
            XCTAssertEqual(transport.collection.last, false)
            XCTAssertNil(defaults.object(forKey: MobileAnalytics.enabledKey))
            XCTAssertNil(defaults.object(forKey: MobileAnalytics.lastActiveDateKey))
            let count = transport.events.count
            analytics.manualRefresh()
            XCTAssertEqual(transport.events.count, count)
        }
    }
}
