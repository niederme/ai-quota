import Foundation
import MobileAccessCore

/// Age always describes the last successful provider response, never the last attempt.
enum WidgetReadingStatus {
    static func isSaved(_ reading: QuotaReading?, needsApp: Bool, updateFailed: Bool, at date: Date) -> Bool {
        guard reading != nil else { return false }
        return needsApp || updateFailed || WidgetFreshness.isOld(reading, at: date)
    }
    static func savedLabel(_ reading: QuotaReading?, at date: Date) -> String {
        guard let reading else { return String(localized: "Saved reading") }
        let age = date.timeIntervalSince(reading.fetchedAt)
        guard age.isFinite, age >= 0 else { return String(localized: "Saved reading") }
        let elapsed = min(age, 315360000)
        if elapsed < 60 { return String(localized: "Saved · just now") }
        if elapsed < 3600 { return String(localized: "Saved · \(Int(elapsed / 60))m ago", comment: "Compact minutes, as in “Saved · 5m ago”.") }
        if elapsed < 86400 { return String(localized: "Saved · \(Int(elapsed / 3600))h ago", comment: "Compact hours, as in “Saved · 3h ago”.") }
        return String(localized: "Saved · \(Int(elapsed / 86400))d ago", comment: "Compact days, as in “Saved · 2d ago”.")
    }
}
