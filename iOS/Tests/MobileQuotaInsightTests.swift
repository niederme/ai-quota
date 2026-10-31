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

    func testFreshFetchRecordsOnceCachedReuseDoesNotAndDisconnectClears() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedQuotaStore(.codex, root: root, namespace: "forecast-test")
        let now = Date.now
        let value = reading(at: now, used: 65, reset: now.addingTimeInterval(4 * 86400))
        let credential = CodexTokens(accessToken: "fixture", refreshToken: nil, accountID: "fixture-workspace",
                                     expiresAt: now.addingTimeInterval(3600))
        try await store.withLease { try store.saveCredentials(credential) }
        do {
            _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in value })
            let url = root.appendingPathComponent("forecast-test-codex-pace-v1.json")
            let first = try Data(contentsOf: url)
            _ = try await store.fetch(CodexTokens.self, source: "test", minimumAge: 300, renew: { $0 }, usage: { _ in
                XCTFail("Cached reuse must not fetch or record again")
                return value
            })
            XCTAssertEqual(try Data(contentsOf: url), first)
            try await store.withLease { try store.clear() }
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        } catch {
            try? await store.withLease { try store.clear() }
            throw error
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testForecastQueryDismissalAndFailureSuppression() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedQuotaStore(.codex, root: root, namespace: "forecast-test")
        let now = Date.now
        let reset = now.addingTimeInterval(4 * 86400)
        let value = reading(at: now, used: 65, reset: reset)
        var history = QuotaForecastHistory()
        for hour in 0..<24 {
            let sample = reading(at: now.addingTimeInterval(Double(hour - 24) * 3600),
                                 used: 25 + Double(hour) * 40 / 24, reset: reset)
            history.record(sample, accountID: "forecast-test", provider: "codex", now: sample.fetchedAt)
        }
        let data = try JSONEncoder().encode(history)
        let credential = CodexTokens(accessToken: "fixture", refreshToken: nil, accountID: "fixture-workspace",
                                     expiresAt: now.addingTimeInterval(3600))
        try await store.withLease {
            try store.saveCredentials(credential)
            try data.write(to: root.appendingPathComponent("forecast-test-codex-pace-v1.json"))
        }
        do {
            _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in value })
            let forecasts = try await store.quotaForecasts(matching: value, now: now)
            let forecast = try XCTUnwrap(forecasts.first)
            let stale = try await store.quotaForecasts(matching: value.identifying("wrong-workspace"), now: now)
            XCTAssertTrue(stale.isEmpty)
            do {
                _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in throw AccessError.http(500) })
                XCTFail("Expected fetch failure")
            } catch AccessError.http(500) { }
            let failed = try await store.quotaForecasts(matching: value, now: now)
            XCTAssertTrue(failed.isEmpty)
            _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in value })
            try await store.dismissForecast(forecast.scope)
            let reopened = try await SharedQuotaStore(.codex, root: root, namespace: "forecast-test")
                .quotaForecasts(matching: value, now: now)
            XCTAssertTrue(reopened.isEmpty)
        } catch {
            try? await store.withLease { try store.clear() }
            throw error
        }
        try await store.withLease { try store.clear() }
        try? FileManager.default.removeItem(at: root)
    }

    func testBannerVisualReview() async throws {
        let now = Date.now
        let reset = now.addingTimeInterval(4 * 86400)
        var history = QuotaForecastHistory()
        for hour in 0...24 {
            let sample = reading(at: now.addingTimeInterval(Double(hour - 24) * 3600), used: 25 + Double(hour) * 40 / 24, reset: reset)
            history.record(sample, accountID: "fixture", provider: "codex", now: sample.fetchedAt)
        }
        let current = reading(at: now, used: 65, reset: reset)
        let forecast = try XCTUnwrap(history.forecasts(for: current, accountID: "fixture", provider: "codex", now: now).first)
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
                    Text("AIQuota").font(.largeTitle.bold()).padding(.bottom, 4)
                    CodexResetNoticeBanner(announcement: CodexResetNotice.demoAnnouncement, openDetails: {}, dismiss: {})
                    MobileQuotaInsightBanner(forecast: forecast, accountLabel: "Personal Codex", dismiss: {})
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
