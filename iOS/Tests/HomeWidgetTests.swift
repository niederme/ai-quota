import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

@MainActor final class HomeWidgetTests: XCTestCase {
    func testAllMacEquivalentLayoutsRenderWithRealisticStates() throws {
        let now = Date.now
        func value(_ service: QuotaService, used: Int, weekly: Int = 55, needsApp: Bool = false) throws -> ProviderReading {
            let data = Data("""
            {"fetchedAt":\(now.timeIntervalSinceReferenceDate),"shortTerm":{"usedPercent":\(used),"durationSeconds":18000,"resetsAt":\(now.addingTimeInterval(3600).timeIntervalSinceReferenceDate)},"weekly":{"usedPercent":\(weekly),"durationSeconds":604800,"resetsAt":\(now.addingTimeInterval(86400).timeIntervalSinceReferenceDate)},"metadata":{"plan":"Plus","balanceUSD":12.50,"usageSpent":45.12,"usageCurrency":"USD"}}
            """.utf8)
            return ProviderReading(service: service, reading: try JSONDecoder().decode(QuotaReading.self, from: data), needsApp: needsApp)
        }
        let samples = try [value(.codex, used: 98), value(.claude, used: 18)]
        let layouts: [(String, HomeQuotaView.Layout, CGFloat, CGFloat)] = [
            ("small", .small, 158, 158), ("single-medium", .singleMedium, 338, 158),
            ("dual-medium", .dualMedium, 338, 158), ("large", .large, 338, 354)]
        for (name, layout, width, height) in layouts {
            for dark in [false, true] {
                let view = HomeQuotaView(values: name == "small" || name == "single-medium" ? [samples[0]] : samples, date: now, layout: layout)
                    .frame(width: width, height: height)
                    .background(HomeWidgetBackground())
                    .background(Color(uiColor: .systemGroupedBackground))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(name)-\(dark ? "dark" : "light").png")
                try image.pngData()?.write(to: path)
                print("HOME_REVIEW " + path.path)
                XCTAssertEqual(image.size.width, width)
                XCTAssertEqual(image.size.height, height)
            }
        }
        for values in [[ProviderReading(service: .codex, reading: nil, needsApp: false)], [try value(.claude, used: 100, needsApp: true)]] {
            let renderer = ImageRenderer(content: HomeQuotaView(values: values, date: now.addingTimeInterval(3601), layout: .singleMedium).frame(width: 338, height: 158))
            XCTAssertNotNil(renderer.uiImage)
        }
        let weeklyLimit = try value(.claude, used: 18, weekly: 100)
        let renderer = ImageRenderer(content: HomeQuotaView(values: [weeklyLimit], date: now, layout: .small)
            .frame(width: 158, height: 158).background(Color(uiColor: .systemGroupedBackground)))
        renderer.scale = 2
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("home-small-weekly-limit.png")
        try XCTUnwrap(renderer.uiImage).pngData()?.write(to: path)
        print("HOME_REVIEW " + path.path)
    }
    func testAlertDefaultsEnableEveryWindowAndPreserveOptOuts() throws {
        let name = UUID().uuidString
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        for service in QuotaService.allCases {
            for window in ["5h", "7d"] {
                for suffix in ["usageEnabled", "limitEnabled"] {
                    let key = "notifications.\(service.rawValue).\(window).\(suffix)"
                    XCTAssertTrue(MobileResetNotifications.alertEnabled(key, store: store))
                    store.set(false, forKey: key)
                    XCTAssertFalse(MobileResetNotifications.alertEnabled(key, store: store))
                    store.set(true, forKey: "notifications.enabled")
                    XCTAssertFalse(MobileResetNotifications.alertEnabled(key, store: store))
                    store.set(true, forKey: key)
                    XCTAssertTrue(MobileResetNotifications.alertEnabled(key, store: store))
                }
            }
        }
    }
    func testPerWindowResetRulesStayIndependent() throws {
        let name = UUID().uuidString
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set("everyReset", forKey: "notifications.codex.5h.resetMode")
        store.set("off", forKey: "notifications.claude.7d.resetMode")
        let codex = MobileResetNotifications.rules(.codex, store: store)
        let claude = MobileResetNotifications.rules(.claude, store: store)
        XCTAssertTrue(try XCTUnwrap(codex["5h"]).allows(usedPercent: 18))
        XCTAssertFalse(try XCTUnwrap(codex["7d"]).allows(usedPercent: 18))
        XCTAssertFalse(try XCTUnwrap(claude["7d"]).allows(usedPercent: 100))
        XCTAssertTrue(try XCTUnwrap(claude["5h"]).allows(usedPercent: 90))
    }
}

extension HomeWidgetTests {
    func testFreePlanSingleWindowLayouts() throws {
        let now = Date.now
        let monthly = try QuotaReading.decode(Data("""
        {"plan_type":"free","rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":2592000,"reset_at":\(now.addingTimeInterval(30 * 86400).timeIntervalSince1970)}}}
        """.utf8), now: now)
        let value = ProviderReading(service: .codex, reading: monthly, needsApp: false)
        func capture<V: View>(_ content: V, name: String, width: CGFloat, height: CGFloat) throws {
            let renderer = ImageRenderer(content: content.frame(width: width, height: height)
                .background(Color(uiColor: .systemGroupedBackground)).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("free-plan-\(name).png")
            try image.pngData()?.write(to: path)
            print("FREE_PLAN_REVIEW " + path.path)
        }
        try capture(ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 370,
            reading: monthly, connected: true, busy: false, error: nil), name: "overview", width: 370, height: 260)
        try capture(HomeQuotaView(values: [value], date: now, layout: .small), name: "small", width: 158, height: 158)
        try capture(HomeQuotaView(values: [value], date: now, layout: .singleMedium), name: "medium", width: 338, height: 158)
        try capture(ServiceDetailsView(value: value, date: now), name: "lock", width: 160, height: 72)
        let weekly = try QuotaReading.decode(Data("""
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":71,"limit_window_seconds":604800,"reset_at":\(now.addingTimeInterval(6 * 86400).timeIntervalSince1970)}}}
        """.utf8), now: now)
        let weeklyValue = ProviderReading(service: .codex, reading: weekly, needsApp: false)
        try capture(ServiceDetailsView(value: weeklyValue, date: now), name: "lock-weekly", width: 160, height: 72)
        try capture(CodexDial(value: weeklyValue, date: now), name: "lock-circular", width: 72, height: 72)
        try capture(CompactQuotaView(service: .codex, reading: weekly, needsApp: false, date: now),
            name: "lock-compact", width: 160, height: 72)
        try capture(HomeQuotaView(values: [weeklyValue], date: now, layout: .small), name: "small-weekly", width: 158, height: 158)
        try capture(HomeQuotaView(values: [weeklyValue], date: now, layout: .large), name: "large-weekly", width: 338, height: 354)
        let full = try QuotaReading.decode(Data("""
        {"plan_type":"free","rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":2592000,"reset_at":\(now.addingTimeInterval(30 * 86400).timeIntervalSince1970)}}}
        """.utf8), now: now)
        try capture(ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 370,
            reading: full, connected: true, busy: false, error: nil), name: "full", width: 370, height: 200)
        try capture(HomeQuotaView(values: [ProviderReading(service: .codex, reading: full, needsApp: false)], date: now, layout: .small),
            name: "small-full", width: 158, height: 158)
        for count in [1, 4, 30] {
            let rows = (0..<count).map { offset in
                let day = CodexUsageHistory.dateString(now.addingTimeInterval(Double(offset - count + 1) * 86400))
                return "{\"date\":\"\(day)\",\"product_surface_usage_values\":{\"cli\":\(offset + 1)}}"
            }.joined(separator: ",")
            let history = try CodexUsageHistory.decode(Data("{\"data\":[\(rows)]}".utf8), now: now)
            try capture(ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 370,
                reading: monthly, connected: true, busy: false, error: nil, history: history),
                name: "history-\(count)", width: 370, height: 260)
        }
        XCTAssertEqual(monthly.windows.count, 1)
        XCTAssertEqual(monthly.primaryWindow?.compactLabel, "m")
    }
}

extension HomeWidgetTests {
    func testProviderAndQuotaShapeKeepRingAnchoredAcrossRegisteredFamilies() throws {
        let now = Date.now
        func reading(dual: Bool) throws -> QuotaReading {
            var windows: [String: Any] = ["secondary_window": ["used_percent": 28, "limit_window_seconds": 604800,
                    "reset_at": now.addingTimeInterval(4 * 86400).timeIntervalSince1970]]
            if dual { windows["primary_window"] = ["used_percent": 12, "limit_window_seconds": 18000,
                    "reset_at": now.addingTimeInterval(3600).timeIntervalSince1970] }
            let value = try QuotaReading.decode(JSONSerialization.data(withJSONObject: ["rate_limit": windows]), now: now)
            return QuotaReading(fetchedAt: now, shortTerm: value.shortTerm, weekly: value.weekly,
                metadata: AccountMetadata(plan: "pro", balanceUSD: 9.40, usageSpent: 12.40, usageCurrency: "USD"))
        }
        func firstRingRow(_ image: UIImage, startY: Int) throws -> Int {
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            for y in startY..<cg.height { for x in 0..<cg.width {
                let i = (y * cg.width + x) * 4
                if (0..<3).contains(where: { abs(Int(pixels[i + $0]) - Int(pixels[$0])) > 10 }) { return y }
            } }
            XCTFail("No ring pixels"); return -1
        }
        let layouts: [(String, HomeQuotaView.Layout, CGFloat, CGFloat)] = [
            ("small-minimum", .small, 158, 158), ("small", .small, 170, 170),
            ("single-medium", .singleMedium, 338, 158), ("dual-medium", .dualMedium, 338, 158),
            ("large", .large, 338, 354)]
        for (name, layout, width, height) in layouts { for dark in [false, true] {
            var ringRows: [Int] = []
            for service in QuotaService.allCases { for dual in [false, true] {
                let value = ProviderReading(service: service, reading: try reading(dual: dual), needsApp: false)
                let values = layout == .dualMedium || layout == .large ? [value, .init(service: service == .codex ? .claude : .codex, reading: value.reading, needsApp: false)] : [value]
                let content = HomeQuotaView(values: values, date: now, layout: layout).frame(width: width, height: height)
                    .background(Color(uiColor: .systemGroupedBackground)).environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.dynamicTypeSize, .accessibility3)
                let renderer = ImageRenderer(content: content); renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                ringRows.append(try firstRingRow(image, startY: layout == .large ? 50 : 0))
                let attachment = XCTAttachment(image: image); attachment.name = "production-home-\(name)-\(service)-\(dual)-\(dark)"; attachment.lifetime = .keepAlways; add(attachment)
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("production-home-\(name)-\(service)-\(dual)-\(dark).png")
                try image.pngData()?.write(to: path); print("WIDGET_REVIEW " + path.path)
            } }
            XCTAssertLessThanOrEqual(try XCTUnwrap(ringRows.max()) - XCTUnwrap(ringRows.min()), 1, "\(name): provider/quota shape moved the ring")
            if layout != .large { XCTAssertLessThanOrEqual(abs(try XCTUnwrap(ringRows.first) - 16), 1, "\(name): chosen painted-ring top inset") }
        } }
    }
}
