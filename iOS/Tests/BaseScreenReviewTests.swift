import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

final class BaseScreenReviewTests: XCTestCase {
    @MainActor func testBaseScreenMaterialsAndAccessibility() async throws {
        let now = Date.now
        func reading(short: Int, week: Int, spent: Double) throws -> QuotaReading {
            try JSONDecoder().decode(QuotaReading.self, from: Data("""
            {"fetchedAt":\(now.timeIntervalSinceReferenceDate),"shortTerm":{"usedPercent":\(short),"durationSeconds":18000,"resetsAt":\(now.addingTimeInterval(3600).timeIntervalSinceReferenceDate)},"weekly":{"usedPercent":\(week),"durationSeconds":604800,"resetsAt":\(now.addingTimeInterval(3 * 86400).timeIntervalSinceReferenceDate)},"metadata":{"plan":"Pro","usageSpent":\(spent),"usageCurrency":"USD"}}
            """.utf8))
        }
        let codex = try reading(short: 78, week: 42, spent: 12.40)
        let claude = try reading(short: 40, week: 5, spent: 154.15)
        let values: [Double] = [2,15,2,0,2,7,5,3,23,3,2,9,4,15,6,30,2,12,1,31,31,15,53,71,56,100,69,27,8,0]
        let rows = values.enumerated().map { i, value in
            "{\"date\":\"\(CodexUsageHistory.dateString(now.addingTimeInterval(Double(i-29)*86400)))\",\"product_surface_usage_values\":{\"cli\":\(value)}}"
        }.joined(separator: ",")
        let history = try CodexUsageHistory.decode(Data("{\"data\":[\(rows)]}".utf8), now: now)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for (name, scheme, size) in [
            ("dark", ColorScheme.dark, DynamicTypeSize.large),
            ("light", .light, .large),
            ("accessible", .dark, .accessibility3)
        ] {
            let content = NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 370,
                            reading: codex, connected: true, busy: false, error: nil, history: history)
                        ProviderDialCardContent(name: "Claude", icon: "logo-claude", availableWidth: 370,
                            reading: claude, connected: true, busy: false, error: nil)
                        Text("Updated 2 minutes ago").font(.caption).foregroundStyle(OverviewStyle.secondary)
                    }.padding(.horizontal, 16).padding(.vertical, 20)
                }
                .background { OverviewBackground().ignoresSafeArea() }
                .navigationTitle("AI Quota").toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Refresh", systemImage: "arrow.clockwise") {}.tint(OverviewStyle.primary) }
                    ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "gearshape") {}.tint(OverviewStyle.primary) }
                }
            }.tint(Color("OverviewAccent"))
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await Task.sleep(for: .milliseconds(700))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Base screen \(name)"; attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("base-screen-\(name).png")
            try image.pngData()?.write(to: path)
            print("BASE_SCREEN_REVIEW " + path.path)
            XCTAssertGreaterThan(image.size.height, 400)
        }
    }
    @MainActor func testCodexDetailReview() async throws {
        let now = Date.now
        let reading = try JSONDecoder().decode(QuotaReading.self, from: Data("""
        {"fetchedAt":\(now.timeIntervalSinceReferenceDate),"weekly":{"usedPercent":12,"durationSeconds":604800,"resetsAt":\(now.addingTimeInterval(86400).timeIntervalSinceReferenceDate)},"metadata":{"plan":"Pro","usageSpent":162.11,"usageCurrency":"USD"}}
        """.utf8))
        let history = try CodexUsageHistory.decode(Data("""
        {"data":[{"date":"\(CodexUsageHistory.dateString(now))","product_surface_usage_values":{"cli":82,"desktop_app":18},"models":[{"model":"gpt-6-astra","credits":82},{"model":"gpt-5.6-sol","credits":14},{"model":"gpt-5.6-terra","credits":4}]}]}
        """.utf8), now: now)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for (name, scheme, size) in [("dark", ColorScheme.dark, DynamicTypeSize.large), ("light", .light, .large), ("accessible", .dark, .accessibility3)] {
            let content = ServiceAccountSheet(showsClose: false) {
                ServiceDetailContent(name: "Codex", icon: "logo-openai", reading: reading,
                    connected: true, busy: false, error: nil, failure: nil, history: history, refresh: {}) { Text("Account") }
            }.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(800))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("codex-detail-\(name).png")
            try image.pngData()?.write(to: path)
            print("DETAIL_REVIEW " + path.path)
            window.isHidden = true
        }
        previous?.makeKey()
    }
    @MainActor func testCodexRefreshSkeletonReview() async throws {
        let now = Date.now
        let reading = try JSONDecoder().decode(QuotaReading.self, from: Data("""
        {"fetchedAt":\(now.timeIntervalSinceReferenceDate),"weekly":{"usedPercent":12,"durationSeconds":604800,"resetsAt":\(now.addingTimeInterval(86400).timeIntervalSinceReferenceDate)},"metadata":{"plan":"Pro","usageSpent":162.11,"usageCurrency":"USD"}}
        """.utf8))
        let history = try CodexUsageHistory.decode(Data("""
        {"data":[{"date":"\(CodexUsageHistory.dateString(now))","product_surface_usage_values":{"cli":82,"desktop_app":18},"models":[{"model":"gpt-6-astra","credits":82},{"model":"gpt-5.6-sol","credits":14},{"model":"gpt-5.6-terra","credits":4}]}]}
        """.utf8), now: now)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for (name, scheme, size) in [("dark", ColorScheme.dark, DynamicTypeSize.large), ("light", .light, .large), ("accessible", .dark, .accessibility3)] {
            let content = ServiceAccountSheet(showsClose: false) {
                ServiceDetailContent(name: "Codex", icon: "logo-openai", reading: reading,
                    connected: true, busy: true, error: nil, failure: nil, history: history, refresh: {}) { Text("Account") }
            }.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(800))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("codex-skeleton-\(name).png")
            try image.pngData()?.write(to: path)
            print("DETAIL_REVIEW " + path.path)
            window.isHidden = true
        }
        previous?.makeKey()
    }
    @MainActor func testClaudeDetailReview() async throws {
        let now = Date.now
        let reading = try JSONDecoder().decode(QuotaReading.self, from: Data("""
        {"fetchedAt":\(now.timeIntervalSinceReferenceDate),"weekly":{"usedPercent":12,"durationSeconds":604800,"resetsAt":\(now.addingTimeInterval(86400).timeIntervalSinceReferenceDate)},"metadata":{"plan":"Pro","usageSpent":162.11,"usageCurrency":"USD"}}
        """.utf8))
        let history = try CodexUsageHistory.decode(Data("""
        {"data":[{"date":"\(CodexUsageHistory.dateString(now))","product_surface_usage_values":{"cli":82,"desktop_app":18},"models":[{"model":"gpt-6-astra","credits":82},{"model":"gpt-5.6-sol","credits":14},{"model":"gpt-5.6-terra","credits":4}]}]}
        """.utf8), now: now)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for (name, scheme, size) in [("dark", ColorScheme.dark, DynamicTypeSize.large), ("light", .light, .large), ("accessible", .dark, .accessibility3)] {
            let content = ServiceAccountSheet(showsClose: false) {
                ServiceDetailContent(name: "Claude", icon: "logo-claude", reading: reading,
                    connected: true, busy: false, error: nil, failure: nil, history: history, refresh: {}) { Text("Account") }
            }.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(800))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("claude-detail-\(name).png")
            try image.pngData()?.write(to: path)
            print("DETAIL_REVIEW " + path.path)
            window.isHidden = true
        }
        previous?.makeKey()
    }
    @MainActor func testAccountFormReview() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: ServiceAccountSheet {
            AccountConnectionForm(plan: "Pro", updated: .now, busy: false,
                needsReconnect: false, error: nil, retry: {}, reconnect: {}, disconnect: {})
                .navigationTitle("Codex account").navigationBarTitleDisplayMode(.inline)
        }.environment(\.colorScheme, .dark))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(800))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("account-form.png")
        try image.pngData()?.write(to: path)
        print("ACCOUNT_REVIEW " + path.path)
    }
    @MainActor func testWidgetGuideReview() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: ServiceAccountSheet {
            LockScreenSetupView()
        }.environment(\.colorScheme, .dark))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(800))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("widget-guide.png")
        try image.pngData()?.write(to: path)
        print("WIDGET_REVIEW " + path.path)
    }
    @MainActor func testServiceAccountSheetsPresentAndDismiss() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for service in ["Codex", "Claude", "Settings"] {
            func content(_ isPresented: Bool) -> some View {
                Text("Overview remains underneath")
                .sheet(isPresented: .constant(isPresented)) {
                    ServiceAccountSheet(showsClose: service == "Settings") {
                        if service == "Settings" {
                            MobileSettingsView(codex: ProbeModel(), claude: ClaudeProbeModel(), onboarding: OnboardingProgress())
                        } else {
                        ServiceDetailContent(name: service, icon: service == "Codex" ? "logo-openai" : "logo-claude",
                            reading: nil, connected: false, busy: false, error: nil, failure: nil, refresh: {}) {
                            if service == "Codex" { ProbeView(model: ProbeModel()) }
                            else { ClaudeProbeView(model: ClaudeProbeModel()) }
                        }
                        }
                    }
                }
                .environment(\.colorScheme, .dark)
            }
            let host = UIHostingController(rootView: content(true))
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await Task.sleep(for: .milliseconds(900))
            let presented = try XCTUnwrap(host.presentedViewController, "Service must be presented modally")
            XCTAssertNotNil(presented.presentationController)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(service) account sheet"
            attachment.lifetime = .keepAlways
            add(attachment)
            host.rootView = content(false)
            try await Task.sleep(for: .milliseconds(700))
            XCTAssertNil(host.presentedViewController)
        }
    }

}
