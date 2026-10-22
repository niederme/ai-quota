import Foundation

public struct UsageAlertState: Codable, Sendable {
    public var windowEnd: Date
    public var highestNotified: Double
    public init(windowEnd: Date, highestNotified: Double = 0) {
        self.windowEnd = windowEnd; self.highestNotified = highestNotified
    }
    /// A corrected future reset time is still the same window. Only a completed
    /// window can rearm an alert; otherwise timestamp jitter could cause duplicates.
    public mutating func updateWindow(end: Date, now: Date) {
        guard end > now else { return }
        if windowEnd <= now { highestNotified = 0 }
        windowEnd = end
    }

    /// One alert per window. Raising the threshold after delivery does not send another alert.
    /// highestNotified remains Codable-compatible with the previous escalating-alert state.
    public func next(used: Double, now: Date, enabled: Bool, threshold: Double = 90) -> Double? {
        guard enabled, windowEnd > now, used.isFinite, used >= 0, highestNotified == 0 else { return nil }
        let threshold = min(100, max(5, threshold.isFinite ? threshold : 90))
        return used >= threshold ? threshold : nil
    }
}
