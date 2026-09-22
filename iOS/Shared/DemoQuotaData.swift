import Foundation
import WidgetKit
import MobileAccessCore

/// Sample data is generated in memory and never written to the live account stores.
enum DemoQuotaData {
    static let enabledKey = "demo.enabled"
    static var defaults: UserDefaults { UserDefaults(suiteName: WidgetStore.group) ?? .standard }
    static var isEnabled: Bool { defaults.bool(forKey: enabledKey) }
    static func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func reading(_ service: QuotaService, now: Date = .now) -> QuotaReading {
        let short = service == .codex ? 38 : 72
        let week = service == .codex ? 61 : 44
        let payload = """
        {"rate_limit":{"primary_window":{"used_percent":\(short),"limit_window_seconds":18000,"reset_at":\(Int(now.addingTimeInterval(7200).timeIntervalSince1970))},"secondary_window":{"used_percent":\(week),"limit_window_seconds":604800,"reset_at":\(Int(now.addingTimeInterval(259200).timeIntervalSince1970))}}}
        """
        // This fixed fixture uses the same quota decoder as live readings.
        let value = try! QuotaReading.decode(Data(payload.utf8), now: now)
        return QuotaReading(fetchedAt: now, shortTerm: value.shortTerm, weekly: value.weekly,
            metadata: AccountMetadata(plan: "Demo", balanceUSD: nil, usageSpent: nil, usageCurrency: nil))
    }

    static func history(now: Date = .now) -> CodexUsageHistory {
        let rows: [[String: Any]] = (0..<30).reversed().map { offset in
            let credits = Double([32, 48, 21, 64, 53, 18, 8][offset % 7])
            return ["date": CodexUsageHistory.dateString(now.addingTimeInterval(-Double(offset) * 86400)),
                    "product_surface_usage_values": ["cli": credits * 0.7, "web": credits * 0.3]]
        }
        return try! CodexUsageHistory.decode(JSONSerialization.data(withJSONObject: ["data": rows]), now: now)
    }
}
