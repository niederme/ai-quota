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
