import Foundation
import MobileAccessCore

/// Age always describes the last successful provider response, never the last attempt.
enum WidgetReadingStatus {
    static func isSaved(_ reading: QuotaReading?, needsApp: Bool, updateFailed: Bool, at date: Date) -> Bool {
        guard reading != nil else { return false }
        return needsApp || updateFailed || WidgetFreshness.isOld(reading, at: date)
    }
    static func savedLabel(_ reading: QuotaReading?, at date: Date) -> String {
        guard let reading else { return "Saved reading" }
        let age = date.timeIntervalSince(reading.fetchedAt)
        guard age.isFinite, age >= 0 else { return "Saved reading" }
        let elapsed = min(age, 315360000)
        let suffix = elapsed < 60 ? "just now" : elapsed < 3600 ? "\(Int(elapsed / 60))m ago" : elapsed < 86400 ? "\(Int(elapsed / 3600))h ago" : "\(Int(elapsed / 86400))d ago"
        return "Saved · " + suffix
    }
}
