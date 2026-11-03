import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

@MainActor final class BankedResetForecastTests: XCTestCase {
    private func forecast(_ now: Date, account: String = "pro", identity: String = "workspace-pro") -> QuotaExhaustionForecast {
        .init(scope: .init(accountID: account, provider: "codex", identity: identity, source: "wham", plan: "pro",
                          window: .weekly, resetAt: now.addingTimeInterval(86400)),
              basis: .periodAverage, projectedUsedPercent: 140, validUntil: now.addingTimeInterval(3600))
    }

    func testInsightUsesOnlyItsOwnVerifiedReadingAndCount() throws {
        let now = Date.now
        let profile = AccountProfile(id: "pro", service: .codex, label: "Codex Pro", isLegacy: false)
        let reading = QuotaReading(fetchedAt: now, shortTerm: nil,
            weekly: .init(usedPercent: 73, durationSeconds: 604800, resetsAt: now.addingTimeInterval(86400)),
            metadata: .init(plan: "pro", balanceUSD: nil, usageSpent: nil, usageCurrency: nil), providerIdentity: "workspace-pro",
            resetCredits: .init(availableCount: 1, applicableAvailableCount: 0))
        let query = MobileQuotaInsightModel.Query(profile: profile, reading: reading, historyFetchedAt: nil, tokensFetchedAt: nil, accountName: "Codex Pro")
        let value = MobileQuotaInsightModel.Insight(forecast: forecast(now), query: query)
        let context = try XCTUnwrap(value.bankedResets)
        XCTAssertEqual(context.availableCount(for: value.forecast, now: now), 1)
        XCTAssertNil(context.availableCount(for: forecast(now, account: "business", identity: "workspace-business"), now: now))
        XCTAssertNil(context.availableCount(for: value.forecast, now: now.addingTimeInterval(301)))
        let privateCopy = QuotaForecastTextFormatter.accessibilitySummary(value.forecast, accountLabel: "Codex", bankedResets: context, now: now)
        XCTAssertTrue(privateCopy.hasPrefix("Codex. You’re on pace to hit your 7d limit early. "))
        XCTAssertTrue(privateCopy.contains("1 reset available"))
        XCTAssertFalse(privateCopy.contains("workspace-pro"))
        XCTAssertFalse(privateCopy.contains("Codex Pro"))
        XCTAssertFalse(privateCopy.contains(".."))
        // A public announcement supplies no account entitlement; unknown count stays absent.
        XCTAssertFalse(QuotaForecastTextFormatter.detail(value.forecast, now: now).contains("resets available"))
        let unknown = QuotaReading(fetchedAt: now, shortTerm: nil, weekly: reading.weekly, providerIdentity: "workspace-pro")
        let refreshed = MobileQuotaInsightModel.Query(profile: profile, reading: unknown, historyFetchedAt: nil, tokensFetchedAt: nil)
        XCTAssertNil(MobileQuotaInsightModel.Insight(forecast: value.forecast, query: refreshed).bankedResets)
    }

    func testBankedResetForecastRenderedLayouts() async throws {
        let now = Date.now
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let counts: [Int?] = [nil, 0, 1, 2, 3]
        for width: CGFloat in [320, 375, 393, 430, 720] {
            for typeSize in [DynamicTypeSize.large, .accessibility5] {
                for (layout, indentsForecast, accountHeading) in [("hanging", true, false), ("unindented", false, false), ("account-heading-suggested-your", false, true), ("production-account-heading", false, false)] {
                    for count in counts {
                        let context = count.map { CodexBankedResetContext(accountID: "pro", providerIdentity: "workspace-pro", credits: .init(availableCount: $0), fetchedAt: now) }
                        let longName = width == 320 && typeSize.isAccessibilitySize
                        let name = longName ? "Codex Pro · A deliberately long custom connection name" : "Codex Pro"
                        let content = Group {
                            if accountHeading {
                                // Suggested “your” grammar belongs only to this exploratory fixture.
                                let suffix = QuotaForecastTextFormatter.title(forecast(now), accountLabel: "").dropFirst(" is on pace to hit its ".count)
                                let sentence = "You’re on pace to hit your " + suffix
                                let detail: String = {
                                    guard let count = context?.availableCount(for: forecast(now), now: now) else {
                                        return QuotaForecastTextFormatter.detail(forecast(now), now: now)
                                    }
                                    let balance = count == 0 ? "You have no banked resets available"
                                        : "You have \(count.formatted()) banked \(count == 1 ? "reset" : "resets") available"
                                    return balance + " • Resets " + QuotaForecastTextFormatter.reset(forecast(now), now: now)
                                }()
                                OverviewAlertRow(title: name, detail: detail, forecastSentence: sentence,
                                    announcement: false, wide: width >= 600, indentsForecast: false, dismiss: {})
                                    .background { OverviewAccountSurface() }
                                    .clipShape(RoundedRectangle(cornerRadius: OverviewStyle.accountRadius))
                                    .accessibilityLabel(name + ". " + sentence + ". " + detail.replacingOccurrences(of: " • ", with: ". "))
                                    .accessibilityHint(context?.availableCount(for: forecast(now), now: now) != nil
                                        ? "Banked resets require separate action in Codex. The time shown is the scheduled refresh." : "")
                            } else {
                                OverviewAlerts(announcement: nil, forecast: forecast(now), accountLabel: name,
                                    bankedResets: context, wide: width >= 600, indentsForecast: indentsForecast, separatesAccountName: layout == "production-account-heading", openDetails: {}, dismissAnnouncement: {})
                            }
                        }
                            .frame(width: width - 32).padding(.horizontal, 16)
                            .padding(.top, 80).padding(.bottom, 34)
                            .background { OverviewBackground() }
                            .environment(\.colorScheme, count == 3 ? .light : .dark)
                            .environment(\.dynamicTypeSize, typeSize)
                        let host = UIHostingController(rootView: content)
                        // This isolated alert host is sized to its content, so do not
                        // add the test device's status/home safe areas afterward.
                        host.safeAreaRegions = []
                        let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
                        XCTAssertEqual(size.width, width, accuracy: 1)
                        XCTAssertGreaterThan(size.height, 44)
                        XCTAssertLessThan(size.height, 4000)
                        let window = UIWindow(windowScene: scene)
                        window.frame = CGRect(origin: .zero, size: size)
                        window.rootViewController = host; window.makeKeyAndVisible()
                        try await Task.sleep(for: .milliseconds(120))
                        host.view.frame = window.bounds; host.view.layoutIfNeeded()
                        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                        }
                        let tag = "viewport-\(layout)-banked-\(Int(width))-\(typeSize.isAccessibilitySize ? "AX5" : "normal")-\(count.map(String.init) ?? "unknown")"
                        let path = FileManager.default.temporaryDirectory.appendingPathComponent(tag + ".png")
                        try image.pngData()?.write(to: path)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = tag
                        attachment.lifetime = .keepAlways
                        add(attachment)
                        print("BANKED_RESET_REVIEW " + path.path)
                        window.isHidden = true
                    }
                }
            }
        }
        previous?.makeKey()
    }
}
