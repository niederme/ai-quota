import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

@MainActor final class MobileQuotaInsightTests: XCTestCase {
    private func reading(at date: Date, used: Double, reset: Date) -> QuotaReading {
        QuotaReading(fetchedAt: date, shortTerm: nil,
            weekly: .init(usedPercent: used, durationSeconds: 604800, resetsAt: reset),
            metadata: .init(plan: "pro", balanceUSD: nil, usageSpent: nil, usageCurrency: nil), providerIdentity: "fixture-workspace")
    }

    func testFreshAndCachedFetchesNeverCreateObservationHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedQuotaStore(.codex, root: root, namespace: "forecast-test")
        let now = Date.now
        let value = reading(at: now, used: 65, reset: now.addingTimeInterval(4 * 86400))
        let credential = CodexTokens(accessToken: "fixture", refreshToken: nil, accountID: "fixture-workspace", expiresAt: now.addingTimeInterval(3600))
        try await store.withLease { try store.saveCredentials(credential) }
        _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in value })
        _ = try await store.fetch(CodexTokens.self, source: "test", minimumAge: 300, renew: { $0 }, usage: { _ in
            XCTFail("Cached reuse must not fetch")
            return value
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("forecast-test-codex-pace-v1.json").path))
        let forecasts = try await store.quotaForecasts(matching: value, now: now)
        XCTAssertEqual(forecasts.first?.basis, .periodAverage)
        try await store.withLease { try store.clear() }
        try? FileManager.default.removeItem(at: root)
    }

    func testForecastDismissalAndFailureSuppressionWithoutCollectedHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedQuotaStore(.codex, root: root, namespace: "forecast-test")
        let now = Date.now
        let value = reading(at: now, used: 65, reset: now.addingTimeInterval(4 * 86400))
        let credential = CodexTokens(accessToken: "fixture", refreshToken: nil, accountID: "fixture-workspace", expiresAt: now.addingTimeInterval(3600))
        try await store.withLease { try store.saveCredentials(credential) }
        _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in value })
        let forecasts = try await store.quotaForecasts(matching: value, now: now)
        let forecast = try XCTUnwrap(forecasts.first)
        let wrongIdentity = try await store.quotaForecasts(matching: value.identifying("different"), now: now)
        XCTAssertTrue(wrongIdentity.isEmpty)
        do {
            _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in throw AccessError.http(500) })
            XCTFail("Expected fetch failure")
        } catch AccessError.http(500) { }
        let failed = try await store.quotaForecasts(matching: value, now: now)
        XCTAssertTrue(failed.isEmpty)
        _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in value })
        try await store.dismissForecast(forecast.scope)
        let reopened = try await SharedQuotaStore(.codex, root: root, namespace: "forecast-test").quotaForecasts(matching: value, now: now)
        XCTAssertTrue(reopened.isEmpty)
        let data = try Data(contentsOf: root.appendingPathComponent("forecast-test-codex-pace-dismissals-v2.json"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("used"))
        try await store.withLease { try store.clear() }
        try? FileManager.default.removeItem(at: root)
    }

    func testExistingProviderHistoryWorksImmediatelyAndRejectsChangedCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedQuotaStore(.codex, root: root, namespace: "forecast-history-test")
        let now = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")!
        let reset = ISO8601DateFormatter().date(from: "2026-11-02T00:00:00Z")!
        let value = reading(at: now, used: 65, reset: reset)
        let credential = CodexTokens(accessToken: "fixture", refreshToken: nil, accountID: "fixture-workspace", expiresAt: .distantFuture)
        try await store.withLease { try store.saveCredentials(credential) }
        _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in value })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rows: [[String: Any]] = (1...28).map { offset in
            let day = now.addingTimeInterval(-Double(offset) * 86400)
            let weight = [1.0,100,10,10,10,100,1][calendar.component(.weekday, from: day) - 1]
            return ["date": CodexUsageHistory.dateString(day), "product_surface_usage_values": ["cli": weight]]
        }
        let history = try CodexUsageHistory.decode(JSONSerialization.data(withJSONObject: ["data": rows]), now: now)
        try await store.publishWidgetHistory(usage: history, matching: credential)
        let forecasts = try await store.quotaForecasts(matching: value, now: now)
        XCTAssertEqual(forecasts.first?.basis, .weeklyPattern)
        let changed = CodexTokens(accessToken: "fixture", refreshToken: nil, accountID: "another-workspace", expiresAt: .distantFuture)
        try await store.withLease { try store.saveCredentials(changed) }
        let mismatched = try await store.quotaForecasts(matching: value, now: now)
        XCTAssertTrue(mismatched.isEmpty)
        try await store.withLease { try store.clear() }
        try? FileManager.default.removeItem(at: root)
    }

    func testUpgradeDeletesLegacyObservationsAndPreservesDismissalEvenOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = SharedQuotaStore(.codex, root: root, namespace: "forecast-test")
        let scope = QuotaForecastScope(accountID: "forecast-test", provider: "codex", identity: "workspace", source: "wham", plan: "pro", window: .weekly, resetAt: .now.addingTimeInterval(86400))
        let json = String(data: try JSONEncoder().encode(scope), encoding: .utf8)!
        let oldURL = root.appendingPathComponent("forecast-test-codex-pace-v1.json")
        try Data("{\"entries\":[{\"scope\":\(json),\"dismissed\":true,\"observations\":[{\"used\":65}]}]}".utf8).write(to: oldURL)
        try await store.withLease {} // No credentials/network needed to migrate.
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        let data = try Data(contentsOf: root.appendingPathComponent("forecast-test-codex-pace-dismissals-v2.json"))
        XCTAssertTrue(try JSONDecoder().decode(QuotaForecastDismissals.self, from: data).contains(scope))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("observations"))
        try? FileManager.default.removeItem(at: root)
    }

    func testBannerVisualReview() async throws {
        let now = Date.now
        let reset = now.addingTimeInterval(4 * 86400)
        let current = reading(at: now, used: 65, reset: reset)
        let forecast = QuotaExhaustionForecast(scope: .init(accountID: "fixture", provider: "codex", identity: "fixture-workspace", source: "wham", plan: "pro", window: .weekly, resetAt: reset),
            basis: .weeklyPattern, projectedUsedPercent: 140, validUntil: now.addingTimeInterval(3600))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for (name, width, scheme, typeSize) in [
            ("phone-dark", 390.0, ColorScheme.dark, DynamicTypeSize.large),
            ("phone-light", 390.0, .light, .large),
            ("ipad-dark", 720.0, .dark, .large),
            ("phone-accessible", 390.0, .dark, .accessibility3)
        ] {
            let content = ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AIQuota").font(.largeTitle.bold())
                        Spacer()
                        OverviewActions(refresh: {}, settings: {})
                    }.padding(.bottom, 4)
                    OverviewAlerts(announcement: CodexResetNotice.demoAnnouncement,
                        forecast: forecast, accountLabel: "Personal Codex", wide: width - 32 >= 600,
                        openDetails: {}, dismissAnnouncement: {}, dismissForecast: {})
                    ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: width - 32,
                        reading: current, connected: true, busy: false, error: nil)
                }.padding(16)
            }.frame(width: width, height: 1000).background { OverviewBackground() }
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, typeSize)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await Task.sleep(for: .milliseconds(300))
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("quota-forecast-\(name).png")
            try image.pngData()?.write(to: path)
            print("QUOTA_FORECAST_REVIEW " + path.path)
        }
    }
}
